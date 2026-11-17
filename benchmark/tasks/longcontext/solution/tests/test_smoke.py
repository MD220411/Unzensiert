"""Smoke tests: every country module answers every function, plus fixed values for Germany."""
import unittest

from shoprules import registry


class SmokeTest(unittest.TestCase):
    def test_every_country_answers(self):
        for code, rules in registry.COUNTRIES.items():
            with self.subTest(country=code):
                self.assertEqual(rules.COUNTRY, code)
                self.assertGreaterEqual(rules.vat_cents(1000, "general"), 0)
                self.assertGreaterEqual(rules.shipping_cents(500, 100), 0)
                self.assertGreaterEqual(rules.region_surcharge("00000"), 0)
                self.assertGreater(rules.delivery_days(), 0)
                self.assertTrue(rules.is_holiday(1, 1))
                self.assertIn("card", rules.payment_methods(100))
                self.assertGreater(rules.return_days("general"), 0)
                self.assertIn(rules.is_restricted("alcohol"), (True, False))
                self.assertTrue(rules.format_price(123450))

    def test_germany(self):
        rules = registry.get("de")
        self.assertEqual(rules.vat_rate("general"), 19)
        self.assertEqual(rules.vat_rate("books"), 5)
        self.assertEqual(rules.vat_cents(1050, "food"), 53)
        self.assertEqual(rules.shipping_cents(1500, 4200), 690)
        self.assertEqual(rules.shipping_cents(1500, 5000), 0)
        self.assertEqual(rules.payment_methods(50001), ["card", "invoice", "paypal", "sepa"])
        self.assertEqual(rules.format_price(123450), "1.234,50 EUR")


class IrelandTest(unittest.TestCase):
    def test_ireland(self):
        rules = registry.get("IE")
        self.assertEqual(rules.vat_rate("ebooks"), 9)
        self.assertEqual(rules.format_price(123450), "EUR 1,234.50")


if __name__ == "__main__":
    unittest.main()
