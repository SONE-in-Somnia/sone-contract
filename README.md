# Sone Game Smart Contract

## Overview

**Sone** is a blockchain-based lucky draw (lottery) game contract that supports only whitelisted ERC20 tokens (native tokens like ETH are not supported). Players deposit supported ERC20 tokens to participate in game rounds. Each round, a winner is randomly selected based on the number of "entries" each player has, which is proportional to their deposit amount (normalized across different tokens).

## Key Features

- **Multi-token Support:** Only approved ERC20 tokens can be used to participate.
- **Fair Draw:** Each round randomly selects a winner, with more entries increasing the chance to win.
- **Security:** Utilizes OpenZeppelin's Ownable, Pausable, and ReentrancyGuard for robust security.
- **Protocol Fee:** A configurable fee is collected from each round and sent to a designated recipient.
- **Admin Controls:** Owner can add/remove supported tokens, pause the contract, and rescue funds in emergencies.
- **No Native Token:** All logic is strictly for ERC20 tokens; native blockchain tokens are not accepted.

## How It Works

1. **Deposit:** Players deposit supported ERC20 tokens to join the current round.
2. **Entries:** Deposits are normalized and converted into entries for the round.
3. **Round Management:** Each round has a maximum number of participants and a set duration.
4. **Draw:** When the round ends or is full, a winner is drawn randomly.
5. **Claim Prize:** The winner can claim all deposited tokens (minus protocol fee).
6. **Next Round:** A new round is automatically initialized.

## Security

- Only whitelisted tokens are accepted.
- All critical functions are protected against reentrancy and can be paused in emergencies.
- Owner and keeper roles are separated for better management.
