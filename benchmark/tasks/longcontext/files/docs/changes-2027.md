# Rule changes for 2027

Apply every item below to the country modules. Amounts in this list are in whole currency
units (EUR 75 means 7500 cents in the code). Nothing else changes: all other rules of all
countries stay exactly as they are, and every module keeps the functions listed in the
README.

1. **Germany:** the reduced VAT rate falls from 7 % to 5 %.
2. **France:** shipping is free from a net order value of EUR 75 (so far EUR 60).
3. **Italy:** heavier parcels are accepted. A new weight band up to 30 kg costs EUR 24.90;
   parcels above 30 kg are still refused.
4. **Spain:** express delivery now takes 1 working day.
5. **Netherlands:** iDEAL is offered for orders of any value.
6. **Poland:** the standard VAT rate falls from 23 % to 22 %.
7. **Sweden:** electronics get the normal return period of 14 days.
8. **Austria:** e-books are taxed at the reduced rate.
9. **All countries that are billed in EUR:** where payment by invoice is offered, it is
   offered up to a net order value of EUR 1000. Countries with other currencies keep their
   invoice limits, and no country gains invoice as a new payment method by this item.
10. **Denmark:** VAT amounts are rounded commercially (half up) instead of down.
11. **Switzerland:** prices are written with an apostrophe as thousands separator
    (`CHF 1'234.50`).
12. **Belgium:** alcohol is no longer restricted. **Luxembourg:** tobacco becomes restricted.
13. **Norway:** the surcharge for Svalbard rises to NOK 190. The surcharge for the rest of
    Northern Norway stays.
14. **Portugal:** 5 October (Republic Day) becomes a public holiday without delivery.
15. **Ireland (IE) is added as a new country**, with a module of its own that is listed in
    the registry and offers the same functions as the others:
    - currency EUR; prices are written like `EUR 1,234.50` (symbol first, decimal point,
      comma as thousands separator)
    - VAT: standard rate 23 %; e-books 9 %; food, books and medicine 0 %; amounts are
      rounded commercially (half up)
    - shipping: up to 2 kg EUR 7.50, up to 10 kg EUR 12.50, up to 25 kg EUR 19.50; heavier
      parcels are refused with `ValueError`; orders from a net value of EUR 60 ship free
      (also in that case a parcel above 25 kg is refused); no regional surcharges
    - delivery in 4 working days, express in 2; public holidays: 1 January, 17 March
      (Saint Patrick's Day), 25 December, 26 December
    - payment: card and paypal for any value, invoice up to EUR 1000
    - returns: 14 days for every category
    - alcohol is restricted
