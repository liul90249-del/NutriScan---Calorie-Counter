import tempfile
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from fastapi import FastAPI
from fastapi.testclient import TestClient
import partner_transactions as module

class InboxTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name)/'inbox.db'
        self.store = module.Inbox(self.path)
    def tearDown(self):
        self.temp.cleanup()
    def transaction(self, **changes):
        values = dict(environment='Production',type='Auto-Renewable Subscription',
            bundleId=module.BUNDLE,productId=sorted(module.SKUS)[0],transactionId='1',
            originalTransactionId='1',appAccountToken=None,purchaseDate=int(time.time()*1000)-1000,
            price=4990,currency='USD',revocationDate=None)
        values.update(changes)
        return SimpleNamespace(**values)
    def test_duplicate_and_restart(self):
        t=self.transaction()
        self.assertFalse(self.store.record(t,'proof')['duplicate'])
        result=module.Inbox(self.path).record(t,'proof')
        self.assertTrue(result['duplicate'])
        self.assertFalse(result['commission_eligible'])
    def test_refund_survives_replay(self):
        t=self.transaction()
        self.store.record(t,'refund',True,('notification','REFUND'))
        result=module.Inbox(self.path).record(t,'old-proof')
        self.assertTrue(result['revoked'])
        with self.store.connect() as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM notifications').fetchone()[0],1)
    def test_conflicts_and_sandbox_isolation(self):
        t=self.transaction();self.store.record(t,'proof')
        with self.assertRaises(ValueError):self.store.record(self.transaction(price=9990),'wrong')
        self.assertFalse(self.store.record(self.transaction(environment='Sandbox'),'sandbox')['duplicate'])
        for change in [dict(bundleId='wrong'),dict(productId='unknown'),dict(type='Consumable'),dict(purchaseDate=0)]:
            with self.assertRaises(ValueError):self.store.record(self.transaction(**change),'wrong')
    def test_invalid_jws_rejected_by_real_apple_verifier(self):
        app=FastAPI();app.include_router(module.router)
        app.dependency_overrides={}
        original=module.inbox
        module.inbox=lambda:self.store
        try:
            response=TestClient(app).post('/v1/partner/transactions',json={'signed_transaction':'invalid.'+'x'*30})
            self.assertEqual(response.status_code,400)
            with self.store.connect() as db:self.assertEqual(db.execute('SELECT COUNT(*) FROM transactions').fetchone()[0],0)
        finally:module.inbox=original

if __name__=='__main__':unittest.main()
