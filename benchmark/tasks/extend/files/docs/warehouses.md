# Change: several warehouses

Until now the tool keeps one quantity per item. From now on an item can be stored in
several warehouses. Everything that worked before must keep working: existing data files
must still load, and calls and commands without a warehouse must behave as before.

## Terms

- A warehouse has a name. Names are normalized like item names (trimmed, lower case).
  An empty name raises `ValueError`.
- The default warehouse is called `main`. Whenever no warehouse is given for adding or
  removing, the default warehouse is meant.

## Store

- `Store.add(item, quantity, warehouse=None)` adds to the given warehouse.
- `Store.remove(item, quantity, warehouse=None)` removes from the given warehouse only.
  If that warehouse does not hold enough, it raises `StockError`, even if other warehouses
  hold the item.
- `Store.stock(item, warehouse=None)` returns the quantity in the given warehouse. Without
  a warehouse it returns the total over all warehouses.
- `Store.items(warehouse=None)` returns the sorted list of `(item, quantity)` for the given
  warehouse. Without a warehouse it returns the totals over all warehouses.
- `Store.warehouses()` returns the sorted names of the warehouses that hold at least one item.
- `Store.transfer(item, quantity, source, target)` moves a quantity from one warehouse to
  another. It raises `StockError` if the source does not hold enough and `ValueError` if
  source and target are the same warehouse or the quantity is not a positive integer.
  A failed transfer changes nothing.
- As before, an item whose quantity drops to 0 disappears.

## Data file

`Store.save` writes the new format:

```json
{"version": 2, "warehouses": {"main": {"bolt": 12}, "north": {"bolt": 4, "nut": 3}}}
```

Warehouses without items are not written. `Store.load` reads the new format and the old
format (`{"items": {...}}`); items of an old file belong to the default warehouse.

## Command line

- `add`, `remove`, `stock` and `list` accept the option `--warehouse NAME` after their
  arguments, with the meaning described above.
- `transfer <item> <quantity> <source> <target>` moves stock and saves the file.
- `warehouses` prints the names from `Store.warehouses()`, one per line.
- `low` keeps using the totals.
- Errors are reported as before (`error: <message>` on stderr, exit code 1).
