"""Verified transaction inbox. Deliberately does not award referral commission."""
import os
from pathlib import Path
import sqlite3
import time
import threading
from functools import lru_cache
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

BUNDLE = 'com.liuzhigang.NutriScan'
APP_ID = 6786940107
SKUS = frozenset((
    'com.liuzhigang.nutriscan.pro.annuala',
    'com.liuzhigang.nutriscan.pro.monthlya',
    'com.liuzhigang.nutriscan.pro.annualpromoa',
))
router = APIRouter(prefix='/v1/partner', tags=['verified-transactions'])

class SignedTransaction(BaseModel):
    signed_transaction: str = Field(min_length=20, max_length=65536)

class SignedNotification(BaseModel):
    signedPayload: str = Field(min_length=20, max_length=131072)

class Inbox:
    def __init__(self, path):
        self.path = str(path)
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with self.connect() as db:
            db.execute('''CREATE TABLE IF NOT EXISTS transactions (
                environment TEXT NOT NULL, transaction_id TEXT NOT NULL,
                original_id TEXT NOT NULL, sku TEXT NOT NULL, account_token TEXT,
                purchased_at INTEGER NOT NULL, price INTEGER, currency TEXT,
                revoked INTEGER NOT NULL, signed_transaction TEXT NOT NULL,
                received_at INTEGER NOT NULL, PRIMARY KEY(environment, transaction_id))''')
            db.execute('''CREATE TABLE IF NOT EXISTS notifications (
                uuid TEXT PRIMARY KEY, kind TEXT NOT NULL, received_at INTEGER NOT NULL)''')

    def connect(self):
        db = sqlite3.connect(self.path, timeout=15)
        db.execute('PRAGMA synchronous=FULL')
        return db

    def record(self, t, proof, refund=False, notification=None):
        env = getattr(t.environment, 'value', t.environment)
        kind = getattr(t.type, 'value', t.type)
        if (t.bundleId != BUNDLE or t.productId not in SKUS
                or kind != 'Auto-Renewable Subscription'
                or env not in ('Production', 'Sandbox')
                or not t.transactionId or not t.originalTransactionId
                or not isinstance(t.purchaseDate, int) or t.purchaseDate <= 0
                or t.purchaseDate > int(time.time()*1000)+300000):
            raise ValueError('Invalid transaction metadata')
        token = str(t.appAccountToken).lower() if t.appAccountToken else None
        revoked = bool(refund or t.revocationDate)
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            row = db.execute('SELECT original_id,sku,account_token,purchased_at,price,currency,revoked FROM transactions WHERE environment=? AND transaction_id=?', (env,t.transactionId)).fetchone()
            fields = (t.originalTransactionId,t.productId,token,t.purchaseDate,t.price,t.currency)
            if row and tuple(row[:6]) != fields:
                raise ValueError('Transaction ownership or amount conflict')
            owners = db.execute('SELECT DISTINCT account_token FROM transactions WHERE environment=? AND original_id=? AND account_token IS NOT NULL', (env,t.originalTransactionId)).fetchall()
            if token and any(owner[0] != token for owner in owners):
                raise ValueError('Subscription ownership conflict')
            revoked = revoked or bool(row and row[6])
            db.execute('''INSERT INTO transactions VALUES (?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(environment,transaction_id) DO UPDATE SET
                revoked=MAX(transactions.revoked,excluded.revoked),
                signed_transaction=excluded.signed_transaction''',
                (env,t.transactionId,*fields[:3],t.purchaseDate,t.price,t.currency,int(revoked),proof,int(time.time())))
            if notification:
                db.execute('INSERT OR IGNORE INTO notifications VALUES (?,?,?)', (*notification,int(time.time())))
        return {'received':True,'duplicate':bool(row),'transaction_id':t.transactionId,
                'environment':env,'revoked':revoked,'attribution_status':'not_bound',
                'commission_eligible':False}

@lru_cache()
def inbox():
    path = os.environ.get('NUTRISCAN_PARTNER_DB_PATH')
    if not path or not Path(path).is_absolute():
        raise HTTPException(503, 'Persistent transaction storage is not configured')
    return Inbox(path)

@lru_cache()
def verifiers():
    from appstoreserverlibrary.signed_data_verifier import SignedDataVerifier
    from appstoreserverlibrary.models.Environment import Environment
    roots = [p.read_bytes() for p in (Path(__file__).parent/'certs').glob('*.cer')]
    if not roots:
        raise HTTPException(503, 'Apple verification certificates unavailable')
    return [SignedDataVerifier(roots, True, env, BUNDLE, APP_ID)
            for env in (Environment.PRODUCTION, Environment.SANDBOX)]

_verification_slots = threading.BoundedSemaphore(4)

def verified(method, proof):
    if not _verification_slots.acquire(blocking=False):
        raise HTTPException(429, 'Verification is busy; retry later')
    try:
        for verifier in verifiers():
            try:
                return getattr(verifier, method)(proof), verifier
            except Exception:
                continue
        raise HTTPException(400, 'Apple signature verification failed')
    finally:
        _verification_slots.release()

@router.post('/transactions')
def receive_transaction(body: SignedTransaction):
    store = inbox()
    transaction, _ = verified('verify_and_decode_signed_transaction', body.signed_transaction)
    try:
        return store.record(transaction,body.signed_transaction)
    except ValueError as error:
        raise HTTPException(409,str(error)) from error

@router.post('/notifications')
def receive_notification(body: SignedNotification):
    store = inbox()
    notification, verifier = verified('verify_and_decode_notification', body.signedPayload)
    identifier = notification.notificationUUID
    kind = getattr(notification.notificationType, 'value', notification.notificationType)
    if not identifier:
        raise HTTPException(400,'Missing notification identifier')
    data = notification.data
    proof = data.signedTransactionInfo if data else None
    if not proof:
        if kind != 'TEST':
            raise HTTPException(400,'Missing signed transaction')
        with store.connect() as db:
            db.execute('INSERT OR IGNORE INTO notifications VALUES (?,?,?)',(identifier,kind,int(time.time())))
        return {'received':True,'notification_type':'TEST'}
    try:
        transaction = verifier.verify_and_decode_signed_transaction(proof)
    except Exception as error:
        raise HTTPException(400,'Apple transaction signature verification failed') from error
    try:
        return store.record(transaction,proof,kind in ('REFUND','REVOKE'),(identifier,kind))
    except ValueError as error:
        raise HTTPException(409,str(error)) from error
