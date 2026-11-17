"""Pricing rules. All amounts are integer cents."""

TAX_RATE_PERCENT = 19


def add_tax(net_cents):
    """Gross amount for a net amount, rounded half up."""
    return (net_cents * (100 + TAX_RATE_PERCENT) + 50) // 100
