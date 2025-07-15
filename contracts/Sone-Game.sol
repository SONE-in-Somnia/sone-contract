// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Sone
 * @notice Sone game supports only whitelisted ERC20 tokens. Native token is not supported.
 * @dev All logic is for ERC20 only. No native token support.
 */

contract Sone is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Enum for round status
    enum RoundStatus {
        None,
        Open,
        Drawing,
        Drawn,
        Cancelled
    }

    /// @notice Structure for a deposit in a round
    struct Deposit {
        uint256 roundId;
        address depositor;
        address token;
        uint256 amount;
        uint256 normalizedValue;
        uint256 entryCount;
        bool withdrawn;
    }

    /// @notice Structure for supported tokens
    struct SupportedToken {
        bool isSupported;
        uint8 decimals;
        bool isActive;
        uint256 minDeposit;
        uint256 ratio; // Ratio to SONE (in basis points, 10000 = 1:1, for depeg handling)
    }

    /// @notice Structure for a round
    struct Round {
        RoundStatus status;
        uint40 startTime;
        uint40 endTime;
        uint40 drawnAt;
        uint40 numberOfParticipants;
        address winner;
        uint256 totalValue;
        uint256 totalEntries;
        uint256 protocolFeeOwed;
        bool prizesClaimed;
        Deposit[] deposits;
        mapping(address => bool) hasParticipated;
        mapping(address => uint256) tokenBalances;
    }

    struct WithdrawalCalldata {
        uint256 roundId;
        uint256[] depositIndices;
    }

    uint256 public currentRoundId;
    uint256 public valuePerEntry;
    uint40 public roundDuration;
    uint16 public protocolFeeBp;
    address public protocolFeeRecipient;
    uint40 public maximumNumberOfParticipantsPerRound;
    mapping(uint256 => Round) public rounds;
    bool public outflowAllowed = true;
    uint256 public constant MINIMUM_PLAYERS_FOR_VALID_ROUND = 2;
    address public keeper;
    mapping(address => SupportedToken) public supportedTokens;
    address[] public tokenList;

    event Deposited(
        address indexed depositor,
        uint256 roundId,
        address indexed token,
        uint256 amount,
        uint256 normalizedValue,
        uint256 entryCount
    );
    event RoundStatusUpdated(uint256 indexed roundId, RoundStatus status);
    event DepositsWithdrawn(
        address indexed depositor,
        uint256 roundId,
        uint256[] depositIndices
    );
    event PrizesClaimed(
        address indexed winner,
        uint256 roundId,
        uint256[] depositIndices
    );
    event ProtocolFeePayment(address indexed token, uint256 amount);
    event RoundValuePerEntryUpdated(uint256 valuePerEntry);
    event RoundDurationUpdated(uint40 roundDuration);
    event ProtocolFeeBpUpdated(uint16 protocolFeeBp);
    event ProtocolFeeRecipientUpdated(address protocolFeeRecipient);
    event OutflowAllowedUpdated(bool isAllowed);
    event MaximumNumberOfParticipantsPerRoundUpdated(
        uint40 maximumNumberOfParticipantsPerRound
    );
    event KeeperUpdated(address indexed newKeeper);
    event SupportedTokenAdded(
        address indexed token,
        uint8 decimals,
        uint256 minDeposit,
        uint256 ratio
    );
    event SupportedTokenEdited(
        address indexed token,
        uint8 decimals,
        uint256 minDeposit,
        uint256 ratio,
        bool isActive
    );
    event SupportedTokenRemoved(address indexed token);
    event FundsRescued(
        address indexed token,
        address indexed to,
        uint256 amount
    );

    /**
     * @notice Constructor to initialize the Sone contract
     */
    constructor(
        address _owner,
        uint40 _roundDuration,
        uint256 _valuePerEntry,
        address _protocolFeeRecipient,
        uint16 _protocolFeeBp,
        uint40 _maximumNumberOfParticipantsPerRound,
        address _keeper
    ) Ownable(_owner) {
        require(_valuePerEntry > 0, "Value per entry must be greater than 0");
        require(
            _protocolFeeRecipient != address(0),
            "Protocol fee recipient cannot be the zero address"
        );
        require(_protocolFeeBp <= 10000, "Protocol fee cannot exceed 100%");

        roundDuration = _roundDuration;
        valuePerEntry = _valuePerEntry;
        protocolFeeRecipient = _protocolFeeRecipient;
        protocolFeeBp = _protocolFeeBp;
        maximumNumberOfParticipantsPerRound = _maximumNumberOfParticipantsPerRound;
        keeper = _keeper;

        _initializeRound(1);
    }

    /**
     * @notice Deposit function for ERC20 tokens only
     * @param token ERC20 token address
     * @param amount Amount to deposit
     */
    function deposit(
        address token,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        require(
            token != address(0),
            "Native token is not supported, only ERC20 allowed"
        );
        require(amount > 0, "ERC20 deposit amount must be greater than 0");

        SupportedToken memory tokenInfo = supportedTokens[token];
        require(
            tokenInfo.isSupported && tokenInfo.isActive,
            "Token not supported or inactive"
        );
        require(amount >= tokenInfo.minDeposit, "Amount below minimum deposit");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        uint256 normalizedValue = _normalizeTokenValue(token, amount);
        _processDeposit(token, amount, normalizedValue);
    }

    /**
     * @notice Internal function to process deposits
     * @param token Token address
     * @param amount Actual token amount
     * @param normalizedValue Normalized value in SONE equivalent
     */
    function _processDeposit(
        address token,
        uint256 amount,
        uint256 normalizedValue
    ) internal {
        uint256 roundId = currentRoundId;
        Round storage round = rounds[roundId];

        // If this is the first deposit in the open round, set the start and end time
        if (round.status == RoundStatus.Open && round.endTime == 0) {
            round.startTime = uint40(block.timestamp);
            round.endTime = uint40(block.timestamp + roundDuration);
        }

        // Make sure the round is still open
        require(
            round.status == RoundStatus.Open,
            "Round is not open for deposits"
        );
        require(block.timestamp < round.endTime, "Round has passed end time");
        require(
            round.numberOfParticipants < maximumNumberOfParticipantsPerRound,
            "Round is full"
        );

        // Calculate entries based on normalized value
        uint256 entryCount = normalizedValue / valuePerEntry;
        require(
            entryCount > 0,
            "Deposit must be at least the value of one entry"
        );

        // Add deposit
        round.deposits.push(
            Deposit({
                roundId: roundId,
                depositor: msg.sender,
                token: token,
                amount: amount,
                normalizedValue: normalizedValue,
                entryCount: entryCount,
                withdrawn: false
            })
        );

        // Update round data
        round.totalValue += normalizedValue;
        round.totalEntries += entryCount;
        round.tokenBalances[token] += amount;

        // Update participant count if this is a new participant
        if (!round.hasParticipated[msg.sender]) {
            round.numberOfParticipants++;
            round.hasParticipated[msg.sender] = true;
        }

        // Check if the round is full
        if (round.numberOfParticipants >= maximumNumberOfParticipantsPerRound) {
            _transitionRoundToDrawing(roundId);
        }

        emit Deposited(
            msg.sender,
            roundId,
            token,
            amount,
            normalizedValue,
            entryCount
        );
    }

    /**
     * @notice Normalize token value to SONE equivalent with depeg ratio
     * @param token Token address
     * @param amount Token amount
     * @return Normalized value in SONE equivalent
     */
    function _normalizeTokenValue(
        address token,
        uint256 amount
    ) internal view returns (uint256) {
        SupportedToken memory tokenInfo = supportedTokens[token];
        require(tokenInfo.isSupported, "Token not supported");

        uint256 normalizedAmount;

        // Normalize to 18 decimals (SONE equivalent)
        if (tokenInfo.decimals < 18) {
            normalizedAmount = amount * (10 ** (18 - tokenInfo.decimals));
        } else if (tokenInfo.decimals > 18) {
            normalizedAmount = amount / (10 ** (tokenInfo.decimals - 18));
        } else {
            normalizedAmount = amount; // Already 18 decimals
        }

        // Apply ratio for depeg handling
        return (normalizedAmount * tokenInfo.ratio) / 10000;
    }

    /**
     * @notice Add a new supported token
     * @param token Token address
     * @param decimals Token decimals
     * @param minDeposit Minimum deposit amount
     * @param ratio Ratio to SONE in basis points (10000 = 1:1)
     */
    function addSupportedToken(
        address token,
        uint8 decimals,
        uint256 minDeposit,
        uint256 ratio
    ) external onlyOwner {
        require(token != address(0), "Native token is not supported");
        require(!supportedTokens[token].isSupported, "Token already supported");
        require(ratio > 0 && ratio <= 50000, "Invalid ratio");

        supportedTokens[token] = SupportedToken({
            isSupported: true,
            decimals: decimals,
            isActive: true,
            minDeposit: minDeposit,
            ratio: ratio
        });

        tokenList.push(token);
        emit SupportedTokenAdded(token, decimals, minDeposit, ratio);
    }

    /**
     * @notice Edit an existing supported token
     * @param token Token address
     * @param decimals Token decimals
     * @param minDeposit Minimum deposit amount
     * @param ratio Ratio to SONE in basis points
     * @param isActive Whether token is active
     */
    function editSupportedToken(
        address token,
        uint8 decimals,
        uint256 minDeposit,
        uint256 ratio,
        bool isActive
    ) external onlyOwner {
        require(supportedTokens[token].isSupported, "Token not supported");
        require(ratio > 0 && ratio <= 50000, "Invalid ratio");

        supportedTokens[token].decimals = decimals;
        supportedTokens[token].minDeposit = minDeposit;
        supportedTokens[token].ratio = ratio;
        supportedTokens[token].isActive = isActive;

        emit SupportedTokenEdited(token, decimals, minDeposit, ratio, isActive);
    }

    /**
     * @notice Remove a supported token
     * @param token Token address to remove
     */
    function removeSupportedToken(address token) external onlyOwner {
        require(token != address(0), "Native token is not supported");
        require(supportedTokens[token].isSupported, "Token not supported");

        delete supportedTokens[token];

        // Remove from tokenList array
        for (uint256 i = 0; i < tokenList.length; i++) {
            if (tokenList[i] == token) {
                tokenList[i] = tokenList[tokenList.length - 1];
                tokenList.pop();
                break;
            }
        }

        emit SupportedTokenRemoved(token);
    }

    /**
     * @notice Get all supported tokens
     * @return Array of supported token addresses
     */
    function getSupportedTokens() external view returns (address[] memory) {
        address[] memory allTokens = new address[](tokenList.length);
        for (uint256 i = 0; i < tokenList.length; i++) {
            allTokens[i] = tokenList[i];
        }
        return allTokens;
    }

    /**
     * @notice Emergency function to rescue funds from the contract
     * @param token Token address (không còn address(0))
     * @param to Recipient address
     * @param amount Amount to rescue
     */
    function rescueFunds(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(to != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than 0");

        // Xoá hoàn toàn rescue MON, chỉ còn rescue ERC20
        if (token == address(0)) {
            revert("Native token is not supported");
        } else {
            // Rescue ERC20 token
            IERC20 tokenContract = IERC20(token);
            require(
                tokenContract.balanceOf(address(this)) >= amount,
                "Insufficient token balance"
            );
            tokenContract.safeTransfer(to, amount);
        }

        emit FundsRescued(token, to, amount);
    }

    /**
     * @notice Internal function to transfer tokens (SONE or ERC20)
     */
    function _transferTokens(
        address token,
        address to,
        uint256 amount
    ) internal {
        require(token != address(0), "Native token is not supported");
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice Draw the winner for the current round
     */
    function drawWinner() external nonReentrant onlyKeeper {
        uint256 roundId = currentRoundId;
        Round storage round = rounds[roundId];

        // Check if the round is ready to be drawn
        if (
            round.status == RoundStatus.Open && block.timestamp >= round.endTime
        ) {
            _transitionRoundToDrawing(roundId);
        }

        require(
            round.status == RoundStatus.Drawing,
            "Round is not in drawing state"
        );

        // Add this check to prevent drawing a winner multiple times
        require(
            round.winner == address(0),
            "Winner already drawn for this round"
        );

        // If there are less than minimum required players, cancel the round
        if (round.numberOfParticipants < MINIMUM_PLAYERS_FOR_VALID_ROUND) {
            _cancelRound(roundId);
            return;
        }

        // Select winner using a simplified randomness source
        uint256 randomNumber = uint256(
            keccak256(
                abi.encodePacked(
                    blockhash(block.number - 1),
                    block.timestamp,
                    block.prevrandao
                )
            )
        );

        uint256 winningEntry = randomNumber % round.totalEntries;
        address winner = _findWinnerByEntry(roundId, winningEntry);

        round.winner = winner;
        round.drawnAt = uint40(block.timestamp);
        round.status = RoundStatus.Drawn;

        // Calculate protocol fee
        round.protocolFeeOwed = (round.totalValue * protocolFeeBp) / 10000;

        emit RoundStatusUpdated(roundId, RoundStatus.Drawn);

        // Initialize the next round
        _initializeRound(roundId + 1);
    }

    /**
     * @notice Claim prizes as the winner of a round (multi-token support)
     * @param withdrawalCalldata The round and deposit indices to claim
     */
    function claimPrizes(
        WithdrawalCalldata calldata withdrawalCalldata
    ) external nonReentrant {
        require(outflowAllowed, "Outflow of funds is not allowed");

        uint256 roundId = withdrawalCalldata.roundId;
        Round storage round = rounds[roundId];

        require(round.status == RoundStatus.Drawn, "Round is not drawn");
        require(msg.sender == round.winner, "Only the winner can claim prizes");

        // Check that prizes haven't already been claimed
        require(!round.prizesClaimed, "Prizes already claimed");

        // Mark prizes as claimed to prevent re-entrancy
        round.prizesClaimed = true;

        // Calculate and distribute prizes for each token
        _distributePrizes(roundId);

        // Mark specific deposits as withdrawn if provided
        for (uint256 i = 0; i < withdrawalCalldata.depositIndices.length; i++) {
            uint256 depositIndex = withdrawalCalldata.depositIndices[i];
            if (depositIndex < round.deposits.length) {
                round.deposits[depositIndex].withdrawn = true;
            }
        }

        emit PrizesClaimed(
            msg.sender,
            roundId,
            withdrawalCalldata.depositIndices
        );
    }

    /**
     * @notice Internal function to distribute prizes in multiple tokens
     */
    function _distributePrizes(uint256 roundId) internal {
        Round storage round = rounds[roundId];

        // Get all unique tokens in this round
        address[] memory roundTokens = _getRoundTokens(roundId);

        for (uint256 i = 0; i < roundTokens.length; i++) {
            address token = roundTokens[i];
            uint256 tokenBalance = round.tokenBalances[token];

            if (tokenBalance > 0) {
                // Calculate protocol fee for this token
                uint256 protocolFee = (tokenBalance * protocolFeeBp) / 10000;
                uint256 prizeAmount = tokenBalance - protocolFee;

                // Send protocol fee if greater than 0
                if (protocolFee > 0) {
                    _transferTokens(token, protocolFeeRecipient, protocolFee);
                    emit ProtocolFeePayment(token, protocolFee);
                }

                // Send prize to winner
                if (prizeAmount > 0) {
                    _transferTokens(token, round.winner, prizeAmount);
                }
            }
        }
    }

    /**
     * @notice Get all unique tokens used in a round
     */
    function _getRoundTokens(
        uint256 roundId
    ) internal view returns (address[] memory) {
        Round storage round = rounds[roundId];
        address[] memory tempTokens = new address[](round.deposits.length);
        uint256 uniqueCount = 0;

        for (uint256 i = 0; i < round.deposits.length; i++) {
            address token = round.deposits[i].token;
            bool isUnique = true;

            for (uint256 j = 0; j < uniqueCount; j++) {
                if (tempTokens[j] == token) {
                    isUnique = false;
                    break;
                }
            }

            if (isUnique) {
                tempTokens[uniqueCount] = token;
                uniqueCount++;
            }
        }

        address[] memory roundTokens = new address[](uniqueCount);
        for (uint256 i = 0; i < uniqueCount; i++) {
            roundTokens[i] = tempTokens[i];
        }

        return roundTokens;
    }

    /**
     * @notice Withdraw deposits from a cancelled round (multi-token support)
     * @param withdrawalCalldata The round and deposit indices to withdraw
     */
    function withdrawDeposits(
        WithdrawalCalldata calldata withdrawalCalldata
    ) external nonReentrant {
        require(outflowAllowed, "Outflow of funds is not allowed");

        uint256 roundId = withdrawalCalldata.roundId;
        Round storage round = rounds[roundId];

        require(
            round.status == RoundStatus.Cancelled,
            "Round is not cancelled"
        );

        // Track unique tokens and their amounts
        address[] memory tokensToWithdraw = new address[](
            withdrawalCalldata.depositIndices.length
        );
        uint256[] memory tokenAmounts = new uint256[](
            withdrawalCalldata.depositIndices.length
        );
        uint256 tokenCount = 0;

        for (uint256 i = 0; i < withdrawalCalldata.depositIndices.length; i++) {
            uint256 depositIndex = withdrawalCalldata.depositIndices[i];
            require(
                depositIndex < round.deposits.length,
                "Invalid deposit index"
            );

            Deposit storage userDeposit = round.deposits[depositIndex];
            require(
                userDeposit.depositor == msg.sender,
                "Not the deposit owner"
            );
            require(!userDeposit.withdrawn, "Deposit already withdrawn");

            userDeposit.withdrawn = true;

            // Find or add token to tracking arrays
            bool tokenFound = false;
            for (uint256 j = 0; j < tokenCount; j++) {
                if (tokensToWithdraw[j] == userDeposit.token) {
                    tokenAmounts[j] += userDeposit.amount;
                    tokenFound = true;
                    break;
                }
            }

            if (!tokenFound) {
                tokensToWithdraw[tokenCount] = userDeposit.token;
                tokenAmounts[tokenCount] = userDeposit.amount;
                tokenCount++;
            }
        }

        // Transfer tokens
        for (uint256 i = 0; i < tokenCount; i++) {
            if (tokenAmounts[i] > 0) {
                _transferTokens(
                    tokensToWithdraw[i],
                    msg.sender,
                    tokenAmounts[i]
                );
            }
        }

        emit DepositsWithdrawn(
            msg.sender,
            roundId,
            withdrawalCalldata.depositIndices
        );
    }

    /**
     * @notice Cancel the current round if eligible
     */
    function cancel() external nonReentrant onlyKeeper {
        uint256 roundId = currentRoundId;
        Round storage round = rounds[roundId];

        // Only allow cancellation if end time has passed and there are not enough players
        require(round.status == RoundStatus.Open, "Round is not open");
        require(block.timestamp >= round.endTime, "End time not reached");
        require(
            round.numberOfParticipants < MINIMUM_PLAYERS_FOR_VALID_ROUND,
            "Round has enough participants"
        );

        _cancelRound(roundId);
    }

    /**
     * @notice Get detailed information about a round
     * @param roundId The round ID to get information for
     * @return status The status of the round
     * @return startTime The start time of the round
     * @return endTime The end time of the round
     * @return drawnAt The time the round was drawn
     * @return numberOfParticipants The number of participants in the round
     * @return winner The winner of the round
     * @return totalValue The total value in the round
     * @return totalEntries The total entries in the round
     * @return protocolFeeOwed The protocol fee owed from the round
     * @return prizesClaimed Whether the prizes have been claimed
     */
    function getRoundInfo(
        uint256 roundId
    )
        external
        view
        returns (
            RoundStatus status,
            uint40 startTime,
            uint40 endTime,
            uint40 drawnAt,
            uint40 numberOfParticipants,
            address winner,
            uint256 totalValue,
            uint256 totalEntries,
            uint256 protocolFeeOwed,
            bool prizesClaimed
        )
    {
        Round storage round = rounds[roundId];
        return (
            round.status,
            round.startTime,
            round.endTime,
            round.drawnAt,
            round.numberOfParticipants,
            round.winner,
            round.totalValue,
            round.totalEntries,
            round.protocolFeeOwed,
            round.prizesClaimed
        );
    }

    /**
     * @notice Get all token balances for a specific round
     * @param roundId The round ID to get information for
     * @return tokens Array of token addresses
     * @return balances Array of token balances
     */
    function getRoundTokenBalances(
        uint256 roundId
    )
        external
        view
        returns (address[] memory tokens, uint256[] memory balances)
    {
        Round storage round = rounds[roundId];

        // Get all supported tokens including native MON
        address[] memory allTokens = this.getSupportedTokens();
        tokens = new address[](allTokens.length);
        balances = new uint256[](allTokens.length);

        // Populate arrays with token addresses and balances
        for (uint256 i = 0; i < allTokens.length; i++) {
            tokens[i] = allTokens[i];
            balances[i] = round.tokenBalances[allTokens[i]];
        }

        return (tokens, balances);
    }

    /**
     * @notice Structure for token deposits
     */
    struct TokenDeposit {
        address tokenAddress;
        uint256 amount;
    }

    /**
     * @notice Structure for user deposits
     */
    struct UserDeposits {
        address userAddress;
        TokenDeposit[] deposits;
    }

    /**
     * @notice Get detailed deposit information grouped by user for a specific round
     * @param roundId The round ID to get information for
     * @return users Array of user deposit information
     */
    function getUserDepositsInRound(
        uint256 roundId
    ) external view returns (UserDeposits[] memory users) {
        Round storage round = rounds[roundId];

        // First identify unique users
        address[] memory uniqueUsers = new address[](round.deposits.length);
        uint256 userCount = 0;

        for (uint256 i = 0; i < round.deposits.length; i++) {
            address depositor = round.deposits[i].depositor;
            bool isNewUser = true;

            for (uint256 j = 0; j < userCount; j++) {
                if (uniqueUsers[j] == depositor) {
                    isNewUser = false;
                    break;
                }
            }

            if (isNewUser) {
                uniqueUsers[userCount] = depositor;
                userCount++;
            }
        }

        // Create the result array with the exact number of users
        users = new UserDeposits[](userCount);

        // Initialize user entries
        for (uint256 i = 0; i < userCount; i++) {
            users[i].userAddress = uniqueUsers[i];
        }

        // Count deposits per user first to allocate arrays
        uint256[] memory depositCounts = new uint256[](userCount);

        for (uint256 i = 0; i < round.deposits.length; i++) {
            address depositor = round.deposits[i].depositor;

            for (uint256 j = 0; j < userCount; j++) {
                if (users[j].userAddress == depositor) {
                    depositCounts[j]++;
                    break;
                }
            }
        }

        // Allocate deposit arrays
        for (uint256 i = 0; i < userCount; i++) {
            users[i].deposits = new TokenDeposit[](depositCounts[i]);
        }

        // Fill in deposit details
        uint256[] memory currentIndex = new uint256[](userCount);

        for (uint256 i = 0; i < round.deposits.length; i++) {
            Deposit storage depositData = round.deposits[i];
            address depositor = depositData.depositor;

            for (uint256 j = 0; j < userCount; j++) {
                if (users[j].userAddress == depositor) {
                    users[j].deposits[currentIndex[j]] = TokenDeposit({
                        tokenAddress: depositData.token,
                        amount: depositData.amount
                    });
                    currentIndex[j]++;
                    break;
                }
            }
        }

        return users;
    }

    /**
     * @notice Get deposit information for a round
     * @param roundId The round ID
     * @param depositIndex The deposit index
     * @return depositor The depositor address
     * @return amount The deposit amount
     * @return entryCount The entry count for this deposit
     * @return withdrawn Whether the deposit has been withdrawn
     */
    function getDeposit(
        uint256 roundId,
        uint256 depositIndex
    )
        external
        view
        returns (
            address depositor,
            uint256 amount,
            uint256 entryCount,
            bool withdrawn
        )
    {
        Deposit storage depositData = rounds[roundId].deposits[depositIndex];
        return (
            depositData.depositor,
            depositData.amount,
            depositData.entryCount,
            depositData.withdrawn
        );
    }

    /**
     * @notice Get the total number of deposits in a round
     * @param roundId The round ID
     * @return The number of deposits
     */
    function getDepositsCount(uint256 roundId) external view returns (uint256) {
        return rounds[roundId].deposits.length;
    }

    /**
     * @notice Get all deposits for a specific user in a round
     * @param roundId The round ID
     * @param user The user address
     * @return depositIndices The indices of deposits owned by the user
     */
    function getUserDepositIndices(
        uint256 roundId,
        address user
    ) external view returns (uint256[] memory) {
        Round storage round = rounds[roundId];
        uint256 count = 0;

        // Count deposits for this user
        for (uint256 i = 0; i < round.deposits.length; i++) {
            if (round.deposits[i].depositor == user) {
                count++;
            }
        }

        // Collect deposit indices
        uint256[] memory depositIndices = new uint256[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < round.deposits.length; i++) {
            if (round.deposits[i].depositor == user) {
                depositIndices[index] = i;
                index++;
            }
        }

        return depositIndices;
    }

    /**
     * @notice Update the value per entry
     * @param _valuePerEntry The new value per entry in wei
     */
    function updateValuePerEntry(uint256 _valuePerEntry) external onlyOwner {
        require(_valuePerEntry > 0, "Value per entry must be greater than 0");
        valuePerEntry = _valuePerEntry;
        emit RoundValuePerEntryUpdated(_valuePerEntry);
    }

    /**
     * @notice Update the round duration
     * @param _roundDuration The new round duration in seconds
     */
    function updateRoundDuration(uint40 _roundDuration) external onlyOwner {
        roundDuration = _roundDuration;
        emit RoundDurationUpdated(_roundDuration);
    }

    /**
     * @notice Update the protocol fee basis points
     * @param _protocolFeeBp The new protocol fee in basis points
     */
    function updateProtocolFeeBp(uint16 _protocolFeeBp) external onlyOwner {
        require(_protocolFeeBp <= 10000, "Protocol fee cannot exceed 100%");
        protocolFeeBp = _protocolFeeBp;
        emit ProtocolFeeBpUpdated(_protocolFeeBp);
    }

    /**
     * @notice Update the protocol fee recipient
     * @param _protocolFeeRecipient The new protocol fee recipient address
     */
    function updateProtocolFeeRecipient(
        address _protocolFeeRecipient
    ) external onlyOwner {
        require(
            _protocolFeeRecipient != address(0),
            "Protocol fee recipient cannot be the zero address"
        );
        protocolFeeRecipient = _protocolFeeRecipient;
        emit ProtocolFeeRecipientUpdated(_protocolFeeRecipient);
    }

    /**
     * @notice Toggle the paused state of the contract
     */
    function togglePaused() external onlyOwner {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
    }

    /**
     * @notice Toggle whether outflow of funds is allowed
     */
    function toggleOutflowAllowed() external onlyOwner {
        outflowAllowed = !outflowAllowed;
        emit OutflowAllowedUpdated(outflowAllowed);
    }

    /**
     * @notice Update the maximum number of participants per round
     * @param _maximumNumberOfParticipantsPerRound The new maximum number of participants
     */
    function updateMaximumNumberOfParticipantsPerRound(
        uint40 _maximumNumberOfParticipantsPerRound
    ) external onlyOwner {
        require(
            _maximumNumberOfParticipantsPerRound > 1,
            "Minimum participants must be at least 2"
        );
        maximumNumberOfParticipantsPerRound = _maximumNumberOfParticipantsPerRound;
        emit MaximumNumberOfParticipantsPerRoundUpdated(
            _maximumNumberOfParticipantsPerRound
        );
    }

    /**
     * @notice Initialize a new round
     * @param roundId The round ID to initialize
     */
    function _initializeRound(uint256 roundId) internal {
        Round storage round = rounds[roundId];

        // Basic initialization
        round.status = RoundStatus.Open;

        // Additional fields that should be explicitly initialized
        round.startTime = 0; // Will be set on first deposit
        round.endTime = 0; // Will be set on first deposit
        round.drawnAt = 0;
        round.numberOfParticipants = 0;
        round.winner = address(0);
        round.totalValue = 0;
        round.totalEntries = 0;
        round.prizesClaimed = false;
        // round.deposits is automatically initialized as an empty array

        currentRoundId = roundId;

        emit RoundStatusUpdated(roundId, RoundStatus.Open);
    }

    /**
     * @notice Transition a round to the drawing state
     * @param roundId The round ID to transition
     */
    function _transitionRoundToDrawing(uint256 roundId) internal {
        Round storage round = rounds[roundId];
        round.status = RoundStatus.Drawing;

        emit RoundStatusUpdated(roundId, RoundStatus.Drawing);
    }

    /**
     * @notice Cancel a round
     * @param roundId The round ID to cancel
     */
    function _cancelRound(uint256 roundId) internal {
        Round storage round = rounds[roundId];
        round.status = RoundStatus.Cancelled;

        emit RoundStatusUpdated(roundId, RoundStatus.Cancelled);

        // Initialize the next round
        _initializeRound(roundId + 1);
    }

    /**
     * @notice Find the winner by entry index
     * @param roundId The round ID
     * @param winningEntry The winning entry index
     * @return The winner's address
     */
    function _findWinnerByEntry(
        uint256 roundId,
        uint256 winningEntry
    ) internal view returns (address) {
        Round storage round = rounds[roundId];
        uint256 currentEntry = 0;

        for (uint256 i = 0; i < round.deposits.length; i++) {
            Deposit storage depositData = round.deposits[i];
            uint256 nextEntry = currentEntry + depositData.entryCount;

            if (winningEntry < nextEntry) {
                return depositData.depositor;
            }

            currentEntry = nextEntry;
        }

        // If no winner is found, revert
        revert("No winner found");
    }

    /**
     * @notice Get all participants and their total bet amounts for a round
     * @param roundId The round ID
     * @return participants Array of participant addresses
     * @return amounts Array of total amounts bet by each participant
     */
    function getRoundParticipants(
        uint256 roundId
    )
        external
        view
        returns (address[] memory participants, uint256[] memory amounts)
    {
        Round storage round = rounds[roundId];

        // First gather all unique participants
        address[] memory tempParticipants = new address[](
            round.deposits.length
        );
        uint256 uniqueCount = 0;

        for (uint256 i = 0; i < round.deposits.length; i++) {
            address depositor = round.deposits[i].depositor;
            bool isUnique = true;

            // Check if this depositor is already in our list
            for (uint256 j = 0; j < uniqueCount; j++) {
                if (tempParticipants[j] == depositor) {
                    isUnique = false;
                    break;
                }
            }

            if (isUnique) {
                tempParticipants[uniqueCount] = depositor;
                uniqueCount++;
            }
        }

        // Create properly sized result arrays
        participants = new address[](uniqueCount);
        amounts = new uint256[](uniqueCount);

        // Copy unique participants to result array
        for (uint256 i = 0; i < uniqueCount; i++) {
            participants[i] = tempParticipants[i];
        }

        // Calculate total amount for each participant
        for (uint256 i = 0; i < round.deposits.length; i++) {
            Deposit storage depositData = round.deposits[i];

            // Find the participant in our array
            for (uint256 j = 0; j < uniqueCount; j++) {
                if (participants[j] == depositData.depositor) {
                    amounts[j] += depositData.amount;
                    break;
                }
            }
        }

        return (participants, amounts);
    }

    // Add a modifier to restrict keeper-only functions
    modifier onlyKeeper() {
        require(msg.sender == keeper, "Caller is not the keeper");
        _;
    }

    // Add a function for the owner to update the keeper
    function updateKeeper(address _newKeeper) external onlyOwner {
        require(_newKeeper != address(0), "Invalid keeper address");
        keeper = _newKeeper;
        emit KeeperUpdated(_newKeeper);
    }

    /**
     * @notice Check if a user has withdrawn all their deposits in a specific round
     * @param roundId The round ID to check
     * @param user The user address to check
     * @return hasWithdrawn True if all deposits have been withdrawn, false otherwise
     */
    function hasUserWithdrawnDeposits(
        uint256 roundId,
        address user
    ) external view returns (bool hasWithdrawn) {
        Round storage round = rounds[roundId];
        bool hasDeposits = false;

        // Check all deposits for the user
        for (uint256 i = 0; i < round.deposits.length; i++) {
            Deposit storage depositData = round.deposits[i];

            // If this is a deposit for our user
            if (depositData.depositor == user) {
                hasDeposits = true;
                // If any deposit is not withdrawn, return false
                if (!depositData.withdrawn) {
                    return false;
                }
            }
        }

        // Return true only if user had deposits and all were withdrawn
        return hasDeposits;
    }

    /**
     * @notice Get comprehensive round data including round info, participants, and system parameters
     * @param roundId The round ID to get information for
     * @param userAddress The address of the user to get specific user data
     * @return roundInfo Struct with basic round information
     * @return participants Array of participant addresses
     * @return amounts Array of amounts bet by each participant
     * @return userDepositIndices Array of user's deposit indices
     * @return systemParams Array of system parameters [valuePerEntry, maxPlayers, protocolFeeBp]
     */
    function getRoundData(
        uint256 roundId,
        address userAddress
    )
        external
        view
        returns (
            RoundInfo memory roundInfo,
            address[] memory participants,
            uint256[] memory amounts,
            uint256[] memory userDepositIndices,
            uint256[] memory systemParams
        )
    {
        Round storage round = rounds[roundId];

        // Get round info
        roundInfo = RoundInfo({
            status: round.status,
            startTime: round.startTime,
            endTime: round.endTime,
            drawnAt: round.drawnAt,
            numberOfParticipants: round.numberOfParticipants,
            winner: round.winner,
            totalValue: round.totalValue,
            totalEntries: round.totalEntries,
            protocolFeeOwed: round.protocolFeeOwed,
            prizesClaimed: round.prizesClaimed
        });

        // Get participants data
        (participants, amounts) = _getRoundParticipants(roundId);

        // Get user deposit indices
        userDepositIndices = _getUserDepositIndices(roundId, userAddress);

        // Get system parameters
        systemParams = new uint256[](3);
        systemParams[0] = valuePerEntry;
        systemParams[1] = maximumNumberOfParticipantsPerRound;
        systemParams[2] = protocolFeeBp;

        return (
            roundInfo,
            participants,
            amounts,
            userDepositIndices,
            systemParams
        );
    }

    // Helper function to get user deposit indices (internal version)
    function _getUserDepositIndices(
        uint256 roundId,
        address user
    ) internal view returns (uint256[] memory) {
        Round storage round = rounds[roundId];
        uint256 count = 0;

        // Count deposits for this user
        for (uint256 i = 0; i < round.deposits.length; i++) {
            if (round.deposits[i].depositor == user) {
                count++;
            }
        }

        // Collect deposit indices
        uint256[] memory depositIndices = new uint256[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < round.deposits.length; i++) {
            if (round.deposits[i].depositor == user) {
                depositIndices[index] = i;
                index++;
            }
        }

        return depositIndices;
    }

    // Convert internal participants retrieval to helper function
    function _getRoundParticipants(
        uint256 roundId
    )
        internal
        view
        returns (address[] memory participants, uint256[] memory amounts)
    {
        Round storage round = rounds[roundId];

        // First gather all unique participants
        address[] memory tempParticipants = new address[](
            round.deposits.length
        );
        uint256 uniqueCount = 0;

        for (uint256 i = 0; i < round.deposits.length; i++) {
            address depositor = round.deposits[i].depositor;
            bool isUnique = true;

            // Check if this depositor is already in our list
            for (uint256 j = 0; j < uniqueCount; j++) {
                if (tempParticipants[j] == depositor) {
                    isUnique = false;
                    break;
                }
            }

            if (isUnique) {
                tempParticipants[uniqueCount] = depositor;
                uniqueCount++;
            }
        }

        // Create properly sized result arrays
        participants = new address[](uniqueCount);
        amounts = new uint256[](uniqueCount);

        // Copy unique participants to result array
        for (uint256 i = 0; i < uniqueCount; i++) {
            participants[i] = tempParticipants[i];
        }

        // Calculate total amount for each participant
        for (uint256 i = 0; i < round.deposits.length; i++) {
            Deposit storage depositData = round.deposits[i];

            // Find the participant in our array
            for (uint256 j = 0; j < uniqueCount; j++) {
                if (participants[j] == depositData.depositor) {
                    amounts[j] += depositData.amount;
                    break;
                }
            }
        }

        return (participants, amounts);
    }

    // Create or update a RoundInfo struct to match the changes in the Round struct
    struct RoundInfo {
        RoundStatus status;
        uint40 startTime;
        uint40 endTime;
        uint40 drawnAt;
        uint40 numberOfParticipants;
        address winner;
        uint256 totalValue;
        uint256 totalEntries;
        uint256 protocolFeeOwed;
        bool prizesClaimed;
    }
}
