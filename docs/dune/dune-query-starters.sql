-- Query 1: total raises created
select count(*) as raises_created
from megaeth.logs
where contract_address = 0x45179ee92887e5770e42cd239644bc7b662673af
  and topic0 = 0x1534c73044cdd3dd20469a77da92dd31e4a8feacc12fb3e1f60648dfa4a85651;


-- Query 2: daily raises created from raw logs
select
  date_trunc('day', block_time) as day,
  count(*) as raises_created
from megaeth.logs
where contract_address = 0x45179ee92887e5770e42cd239644bc7b662673af
  and topic0 = 0x1534c73044cdd3dd20469a77da92dd31e4a8feacc12fb3e1f60648dfa4a85651
group by 1
order by 1;


-- Query 3: factory transactions
select
  block_time,
  tx_hash,
  "from",
  "to",
  success
from megaeth.transactions
where "to" = 0x45179ee92887e5770e42cd239644bc7b662673af
order by block_time desc
limit 100;


-- Query 4: creation tx of the factory
select
  block_time,
  tx_hash,
  "from",
  address
from megaeth.creation_traces
where address = 0x45179ee92887e5770e42cd239644bc7b662673af;


-- After factory decoding is approved, replace the schema/table names below with the actual Dune decoded names.
-- Starter examples of what to build next:
--
-- A. raises by day from decoded event table
-- B. capital committed by sale
-- C. successful vs failed raises
-- D. vault token settlement outcomes
