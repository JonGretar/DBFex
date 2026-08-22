# 0002. Use a process-backed filesystem resource owner

- Status: Accepted
- Date: 2026-08-22

## Context

An open database owns a table handle and sometimes a memo handle. The public
value is immutable and may be copied, but `DBF.close/1` must be idempotent and
opening must close every acquired handle after any later parsing failure.
Storing devices directly in copied structs cannot represent shared closed state
or reliably aggregate cleanup across both files.

## Decision

Use one concrete internal `DBF.Resource` process for filesystem-backed tables.
The process:

- opens and owns the table and optional memo devices;
- caches sizes from the opened devices and serves positional exact reads;
- gives every open database one resource identity shared by immutable copies;
- closes every acquired device on transaction rollback;
- makes repeated and concurrent close calls idempotent;
- monitors the process that opened the database and performs best-effort cleanup
  when that owner exits;
- returns contextual `DBF.Error` values rather than exposing devices to parsers.

`DBF.Resource` is a concrete implementation, not a behavior. Binary, generic IO,
and writer adapters are not introduced until a second accepted source requires a
real abstraction.

Header, schema, record, and memo parsers consume bounded binaries or request
positional reads through this resource. They do not own or close devices.

## Consequences

The public database remains an immutable handle while resource lifecycle state
has one mutable identity. Transactional opening and idempotent close no longer
depend on callers retaining an updated struct. The additional process introduces
a small message-passing cost per positional read; this is accepted in favor of
correct ownership and can be measured before considering any optimization.

Future writing or editing remains a separate abstraction. It may reuse format
profiles and schema metadata, but it does not turn this read-only resource into a
read-write database handle.
