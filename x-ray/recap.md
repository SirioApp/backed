# Recap Breve

## Problemi principali

- **Poteri admin troppo forti e immediati**: `AgentRaiseFactory`, `AgentExecutor` e `ContractAllowlist` permettono azioni operative istantanee senza timelock o vincoli aggiuntivi.
- **Break-glass molto permissivo**: `AgentExecutor.setAllowlistEnforced(false)` disattiva insieme target check, selector check e spender check.
- **Superficie critica su `Sale`**: `commit()`, `finalize()` e `claim()` concentrano la logica piu` sensibile di accounting, cap, oversubscription e chiusura finale.
- **Dipendenza forte dal comportamento del collateral**: il protocollo assume transfer esatti e token con comportamento standard; token pausabili, blacklistabili o upgradeabili restano un rischio operativo.
- **Storia git molto debole**: 1 contributor, 0 merge commit, 2 commit totali su branch; poca visibilita` di review o hardening progressivo.

## Cose da modificare prima

1. **Rendere piu` sicuri i poteri privilegiati**
  - aggiungere timelock / multisig almeno su approval, policy executor e allowlist
  - separare meglio i ruoli operativi
2. **Ridurre il rischio del break-glass**
  - evitare un toggle globale cosi` forte
  - se resta, limitarlo o renderlo molto piu` esplicito e tracciabile
3. **Rafforzare i test su `Sale` e `AgentVaultToken`**
  - fuzz su oversubscription, rounding e ultimo claimer
  - invariant test sulla chiusura di `accepted`, `shares` e `refunds`
4. **Rafforzare i test su `AgentExecutor`**
  - invarianti su target bloccati
  - test piu` aggressivi su selector policy e approval recipient policy
5. **Formalizzare le assunzioni sul collateral**
  - documentare chiaramente quali token sono supportati
  - valutare controlli o policy piu` esplicite su token non standard

## Gap di qualità

- **Niente fuzzing**
- **Niente invariant testing**
- **Niente formal verification**
- **Documentazione tecnica ancora leggera**: README e NatSpec ci sono, ma manca una spec vera

## Priorita` pratica

Se devo ordinare il lavoro:

1. `Sale.sol`
2. `AgentExecutor.sol`
3. `AgentVaultToken.sol`
4. `AgentRaiseFactory.sol`
5. governance hardening su admin / allowlist / selector policy

