## Dune

Obiettivo corretto:

1. fare decoding dei contratti
2. aspettare che Dune materializzi le tabelle
3. costruire dashboard/query sopra le tabelle decodificate

MegaETH è supportata da Dune:

- [MegaETH Overview](https://docs.dune.com/data-catalog/evm/megaeth/overview)

Submission UI:

- [https://dune.com/contracts/new](https://dune.com/contracts/new)

Guide ufficiali:

- [Contract Submission Guide](https://docs.dune.com/web-app/decoding/short-guide-contract-submission)
- [How Contract Decoding Works](https://docs.dune.com/web-app/decoding/decoding-contracts)

### Contratti da sottomettere

#### 1. Factory

- chain: `MegaETH`
- address: `0x45179eE92887e5770E42CD239644bc7b662673af`
- project name: `Backed`
- contract name: `AgentRaiseFactory`
- ABI file: [AgentRaiseFactory.abi.json](/Users/lucatropea/Desktop/Backed/app/backend/docs/dune/AgentRaiseFactory.abi.json)

Checkbox consigliati:

- `Enable bytecode matching`: sì
- `Are there several instances of this contract?`: no
- `Is it created by a factory contract?`: no

Perché:

- è la factory principale del protocollo, singola
- vuoi decodificare eventi/funzioni della factory, soprattutto `AgentRaiseCreated`

#### 2. Sale

Da inviare quando esiste almeno un `Sale` creato on-chain.

- chain: `MegaETH`
- address: `sale address` di un progetto reale
- project name: `Backed`
- contract name: `Sale`
- ABI file: [Sale.abi.json](/Users/lucatropea/Desktop/Backed/app/backend/docs/dune/Sale.abi.json)

Checkbox consigliati:

- `Enable bytecode matching`: sì
- `Are there several instances of this contract?`: sì
- `Is it created by a factory contract?`: sì

Perché:

- tutti i `Sale` sono creati dalla stessa factory/deployer
- così Dune può decodificare tutte le future istanze con lo stesso bytecode

#### 3. AgentVaultToken

Da inviare quando esiste almeno un vault token creato dopo una finalize riuscita.

- chain: `MegaETH`
- address: `share token address` reale
- project name: `Backed`
- contract name: `AgentVaultToken`
- ABI file: [AgentVaultToken.abi.json](/Users/lucatropea/Desktop/Backed/app/backend/docs/dune/AgentVaultToken.abi.json)

Checkbox consigliati:

- `Enable bytecode matching`: sì
- `Are there several instances of this contract?`: sì
- `Is it created by a factory contract?`: sì

### Ordine giusto

Adesso:

1. sottometti `AgentRaiseFactory`

Dopo il primo progetto live:

2. sottometti un `Sale`

Dopo la prima finalize riuscita:

3. sottometti un `AgentVaultToken`

### Cosa ottieni

Dopo l’approvazione e la materializzazione:

- eventi factory leggibili come `AgentRaiseCreated`
- eventi sale leggibili come `Committed`, `Finalized`, `Claimed`, `Refunded`
- eventi vault leggibili come `Bootstrapped`, `SaleCompleted`, `SettlementFinalized`

### Stato attuale on-chain

Su mainnet oggi:

- `projectCount()` = `0`

Quindi:

- la factory si può sottomettere subito
- `Sale` e `AgentVaultToken` conviene sottometterli appena esistono indirizzi reali

### Consiglio pratico

Non aspettare il protocollo completo per partire su Dune.

Fai subito:

1. decode della factory
2. dashboard base sulle creazioni raise

Poi estendi il dashboard quando compaiono le prime istanze di `Sale` e `AgentVaultToken`.
