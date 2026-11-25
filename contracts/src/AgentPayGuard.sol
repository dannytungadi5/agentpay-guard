// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title AgentPayGuard
/// @notice Spending rules for an AI agent that pays with a stablecoin, enforced on chain.
///         The owner approves this contract once, then gives each agent a mandate:
///         a total budget, a per-payment cap, an expiry, and a list of merchants it may pay.
///         The owner can revoke at any time. The agent calls `pay`; funds go from the owner
///         straight to the merchant. If any rule fails, the whole call reverts and no money moves.
/// @dev Why on chain: an LLM agent can be tricked by text it reads (a fake invoice, an email,
///      a web page). Rules in the agent's prompt can be talked around. Rules in a contract can't.
///      There is no admin, no owner of this contract, no upgrade path, and no way to move funds
///      except owner -> allowlisted merchant, within the mandate.
contract AgentPayGuard {
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

    constructor(IERC20 token_) {
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
        Mandate storage m = _mandates[owner][msg.sender];
        if (m.expiry == 0) revert NoMandate();
        if (m.revoked) revert Revoked();
        if (block.timestamp >= m.expiry) revert Expired();
        if (!merchantAllowed[owner][msg.sender][merchant]) revert MerchantNotAllowed(merchant);
        if (amount == 0) revert ZeroAmount();
        if (amount > m.perTxCap) revert OverPerTxCap(amount, m.perTxCap);
        uint256 remaining_ = m.budget - m.spent;
        if (amount > remaining_) revert OverBudget(amount, remaining_);
        if (orderPaid[owner][orderId]) revert OrderAlreadyPaid(orderId);

        orderPaid[owner][orderId] = true;
        m.spent += uint128(amount);
        token.safeTransferFrom(owner, merchant, amount);
        emit Paid(owner, msg.sender, merchant, orderId, amount);
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
