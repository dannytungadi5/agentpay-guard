// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title AgentPayGuard
/// @notice Spending rules for an AI agent that pays with a stablecoin, enforced on chain.
///         The owner approves this contract once, then gives each agent a mandate:
///         a total budget, a per-payment cap, an expiry, and a list of merchants it may pay.
///         Optional extras: a rolling 24h limit, and a human-approval step for payments above a
///         threshold (the agent can only request them; the owner releases them).
///         Optional: require every payment to carry an invoice signed by the merchant (EIP-712),
///         so the agent can only pay an invoice the merchant itself issued for that exact amount and order.
///         The owner can revoke at any time. The agent calls `pay`; funds go from the owner
///         straight to the merchant. If any rule fails, the whole call reverts and no money moves.
/// @dev Why on chain: an LLM agent can be tricked by text it reads (a fake invoice, an email,
///      a web page). Rules in the agent's prompt can be talked around. Rules in a contract can't.
///      There is no admin, no owner of this contract, no upgrade path, and no way to move funds
///      except owner -> allowlisted merchant, within the mandate.
contract AgentPayGuard is EIP712 {
    using SafeERC20 for IERC20;

    struct Mandate {
        uint128 budget; // total the agent may spend under this mandate
        uint128 spent; // already spent
        uint128 perTxCap; // max for a single payment
        uint64 expiry; // unix seconds; payments at or after this time revert
        bool revoked;
    }

    IERC20 public immutable token;

    /// owner => agent => mandate
    mapping(address => mapping(address => Mandate)) private _mandates;
    /// owner => agent => merchant => allowed
    mapping(address => mapping(address => mapping(address => bool))) public merchantAllowed;
    /// owner => orderId => paid (an order is paid once, so a replayed or repeated instruction fails)
    mapping(address => mapping(bytes32 => bool)) public orderPaid;

    struct Pending {
        address agent;
        address merchant;
        uint128 amount;
        uint8 status; // 0 none, 1 waiting, 2 approved, 3 rejected
    }

    /// owner => agent => payments above this need the owner's approval (0 = off)
    mapping(address => mapping(address => uint128)) public approvalThreshold;
    /// owner => agent => max spend per rolling 24h window (0 = off)
    mapping(address => mapping(address => uint128)) public dailyLimit;
    mapping(address => mapping(address => uint64)) public windowStart;
    mapping(address => mapping(address => uint128)) public windowSpent;
    /// owner => orderId => payment waiting for approval
    mapping(address => mapping(bytes32 => Pending)) public pending;

    /// owner => agent => agent must present a merchant-signed invoice (use payWithInvoice)
    mapping(address => mapping(address => bool)) public requireSignedInvoice;
    bytes32 public constant INVOICE_TYPEHASH =
        keccak256("Invoice(address merchant,address payer,uint256 amount,bytes32 orderId,uint256 deadline)");

    event InvoiceRuleSet(address indexed owner, address indexed agent, bool required);
    event ApprovalThresholdSet(address indexed owner, address indexed agent, uint256 threshold);
    event DailyLimitSet(address indexed owner, address indexed agent, uint256 limit);
    event PaymentPending(
        address indexed owner, address indexed agent, address indexed merchant, bytes32 orderId, uint256 amount
    );
    event PendingApproved(address indexed owner, bytes32 indexed orderId);
    event PendingRejected(address indexed owner, bytes32 indexed orderId);

    event MandateSet(address indexed owner, address indexed agent, uint256 budget, uint256 perTxCap, uint64 expiry);
    event MerchantSet(address indexed owner, address indexed agent, address indexed merchant, bool allowed);
    event MandateRevoked(address indexed owner, address indexed agent);
    event Paid(
        address indexed owner, address indexed agent, address indexed merchant, bytes32 orderId, uint256 amount
    );

    error ZeroAddress();
    error ZeroAmount();
    error NoMandate();
    error Revoked();
    error Expired();
    error MerchantNotAllowed(address merchant);
    error OverPerTxCap(uint256 amount, uint256 cap);
    error OverBudget(uint256 amount, uint256 remaining);
    error OrderAlreadyPaid(bytes32 orderId);
    error BadExpiry();
    error SignedInvoiceRequired();
    error BadInvoiceSignature();
    error InvoiceExpired();
    error OverDailyLimit(uint256 amount, uint256 left);
    error NotPending(bytes32 orderId);

    constructor(IERC20 token_) EIP712("AgentPayGuard", "1") {
        if (address(token_) == address(0)) revert ZeroAddress();
        token = token_;
    }

    // ---------------- owner actions ----------------

    /// @notice Create or replace a mandate for `agent`. Replacing resets `spent` to 0 and un-revokes.
    function setMandate(address agent, uint128 budget, uint128 perTxCap, uint64 expiry) external {
        if (agent == address(0)) revert ZeroAddress();
        if (expiry <= block.timestamp) revert BadExpiry();
        _mandates[msg.sender][agent] =
            Mandate({budget: budget, spent: 0, perTxCap: perTxCap, expiry: expiry, revoked: false});
        emit MandateSet(msg.sender, agent, budget, perTxCap, expiry);
    }

    /// @notice Allow or disallow `agent` to pay `merchant`.
    function setMerchant(address agent, address merchant, bool allowed) external {
        if (agent == address(0) || merchant == address(0)) revert ZeroAddress();
        merchantAllowed[msg.sender][agent][merchant] = allowed;
        emit MerchantSet(msg.sender, agent, merchant, allowed);
    }

    /// @notice Payments above `threshold` are only requested by the agent; the owner must approve them. 0 = off.
    function setApprovalThreshold(address agent, uint128 threshold) external {
        approvalThreshold[msg.sender][agent] = threshold;
        emit ApprovalThresholdSet(msg.sender, agent, threshold);
    }

    /// @notice Require (or stop requiring) a merchant-signed invoice for every payment by `agent`.
    function setRequireSignedInvoice(address agent, bool required) external {
        requireSignedInvoice[msg.sender][agent] = required;
        emit InvoiceRuleSet(msg.sender, agent, required);
    }

    /// @notice Max the agent may spend in any rolling 24h window. 0 = off.
    function setDailyLimit(address agent, uint128 limit) external {
        dailyLimit[msg.sender][agent] = limit;
        emit DailyLimitSet(msg.sender, agent, limit);
    }

    /// @notice Release a payment the agent requested. All rules are checked again now.
    function approvePending(bytes32 orderId) external {
        Pending storage p = pending[msg.sender][orderId];
        if (p.status != 1) revert NotPending(orderId);
        p.status = 2;
        _spend(msg.sender, p.agent, p.merchant, p.amount);
        emit PendingApproved(msg.sender, orderId);
        emit Paid(msg.sender, p.agent, p.merchant, orderId, p.amount);
    }

    /// @notice Refuse a requested payment. The order id stays used.
    function rejectPending(bytes32 orderId) external {
        Pending storage p = pending[msg.sender][orderId];
        if (p.status != 1) revert NotPending(orderId);
        p.status = 3;
        emit PendingRejected(msg.sender, orderId);
    }

    /// @notice Stop `agent` from paying anything else, now.
    function revoke(address agent) external {
        Mandate storage m = _mandates[msg.sender][agent];
        if (m.expiry == 0) revert NoMandate();
        m.revoked = true;
        emit MandateRevoked(msg.sender, agent);
    }

    // ---------------- agent action ----------------

    /// @notice The agent pays `merchant` from `owner`'s tokens, if every rule passes.
    function pay(address owner, address merchant, uint256 amount, bytes32 orderId) external {
        if (requireSignedInvoice[owner][msg.sender]) revert SignedInvoiceRequired();
        _request(owner, msg.sender, merchant, amount, orderId);
    }

    /// @notice Pay an invoice the merchant signed (EIP-712: merchant, payer = owner, amount, orderId, deadline).
    ///         Works for any agent; required when the owner turned on `requireSignedInvoice`.
    function payWithInvoice(
        address owner,
        address merchant,
        uint256 amount,
        bytes32 orderId,
        uint256 deadline,
        bytes calldata signature
    ) external {
        if (block.timestamp > deadline) revert InvoiceExpired();
        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(INVOICE_TYPEHASH, merchant, owner, amount, orderId, deadline))
        );
        if (!SignatureChecker.isValidSignatureNow(merchant, digest, signature)) revert BadInvoiceSignature();
        _request(owner, msg.sender, merchant, amount, orderId);
    }

    function _request(address owner, address agent, address merchant, uint256 amount, bytes32 orderId) internal {
        Mandate storage m = _mandates[owner][agent];
        if (m.expiry == 0) revert NoMandate();
        if (m.revoked) revert Revoked();
        if (block.timestamp >= m.expiry) revert Expired();
        if (!merchantAllowed[owner][agent][merchant]) revert MerchantNotAllowed(merchant);
        if (amount == 0) revert ZeroAmount();
        if (amount > m.perTxCap) revert OverPerTxCap(amount, m.perTxCap);
        uint256 remaining_ = m.budget - m.spent;
        if (amount > remaining_) revert OverBudget(amount, remaining_);
        if (orderPaid[owner][orderId]) revert OrderAlreadyPaid(orderId);
        orderPaid[owner][orderId] = true;

        uint128 th = approvalThreshold[owner][agent];
        if (th != 0 && amount > th) {
            pending[owner][orderId] = Pending(agent, merchant, uint128(amount), 1);
            emit PaymentPending(owner, agent, merchant, orderId, amount);
            return;
        }
        _spend(owner, agent, merchant, amount);
        emit Paid(owner, agent, merchant, orderId, amount);
    }

    /// @dev Budget, rolling-window and transfer. Used by direct payments and approved ones.
    function _spend(address owner, address agent, address merchant, uint256 amount) internal {
        Mandate storage m = _mandates[owner][agent];
        if (m.revoked) revert Revoked();
        if (block.timestamp >= m.expiry) revert Expired();
        if (!merchantAllowed[owner][agent][merchant]) revert MerchantNotAllowed(merchant);
        uint256 remaining_ = m.budget - m.spent;
        if (amount > remaining_) revert OverBudget(amount, remaining_);
        uint128 dl = dailyLimit[owner][agent];
        if (dl != 0) {
            if (block.timestamp >= uint256(windowStart[owner][agent]) + 1 days) {
                windowStart[owner][agent] = uint64(block.timestamp);
                windowSpent[owner][agent] = 0;
            }
            uint256 left = dl - windowSpent[owner][agent];
            if (amount > left) revert OverDailyLimit(amount, left);
            windowSpent[owner][agent] += uint128(amount);
        }
        m.spent += uint128(amount);
        token.safeTransferFrom(owner, merchant, amount);
    }

    // ---------------- views ----------------

    function mandateOf(address owner, address agent) external view returns (Mandate memory) {
        return _mandates[owner][agent];
    }

    function remaining(address owner, address agent) external view returns (uint256) {
        Mandate storage m = _mandates[owner][agent];
        return m.budget - m.spent;
    }
}
