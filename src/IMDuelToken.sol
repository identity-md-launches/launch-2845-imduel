// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title IMDuel (IMDUEL)
/// @notice A fixed-supply ERC-20. The whole supply of 1,000,000,000 IMDUEL (18 decimals) is minted
///         once, in the constructor, to the deployer. There is no owner, no minter, no pause, no
///         blocklist and no transfer fee: after deployment nobody holds any power over the token or
///         over any holder's balance, and the supply can never grow.
/// @dev    Self-contained ERC-20 (EIP-20) implementation. No library calls, no delegatecall, no
///         selfdestruct. `transferFrom` spends an allowance granted by `from` to `msg.sender` only.
contract IMDuelToken {
    // ------------------------------------------------------------------------
    // Metadata and supply
    // ------------------------------------------------------------------------

    /// @notice Token name returned by `name()`.
    string public constant NAME = "IMDuel";

    /// @notice Token symbol returned by `symbol()`.
    string public constant SYMBOL = "IMDUEL";

    /// @notice Number of decimals returned by `decimals()`.
    uint8 public constant DECIMALS = 18;

    /// @notice The whole supply, minted once in the constructor: 1,000,000,000 tokens in minor units.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** uint256(DECIMALS);

    // ------------------------------------------------------------------------
    // Errors
    // ------------------------------------------------------------------------

    /// @notice A transfer was attempted from an account whose balance does not cover it.
    error InsufficientBalance(address from, uint256 balance, uint256 needed);

    /// @notice A `transferFrom` was attempted by a spender whose allowance does not cover it.
    error InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    /// @notice The zero address was given where a real sender is required.
    error InvalidSender(address sender);

    /// @notice The zero address was given where a real receiver is required.
    error InvalidReceiver(address receiver);

    /// @notice The zero address was given where a real allowance owner is required.
    error InvalidApprover(address approver);

    /// @notice The zero address was given where a real spender is required.
    error InvalidSpender(address spender);

    // ------------------------------------------------------------------------
    // Events (EIP-20)
    // ------------------------------------------------------------------------

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // ------------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------------

    mapping(address account => uint256) private _balances;
    mapping(address owner => mapping(address spender => uint256)) private _allowances;

    // ------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------

    /// @notice Mints the entire fixed supply to the deployer (`msg.sender`). Nothing can mint afterwards.
    /// @dev    Takes no arguments and makes no external calls, so it deploys on an empty chain.
    constructor() {
        _balances[msg.sender] = TOTAL_SUPPLY;
        emit Transfer(address(0), msg.sender, TOTAL_SUPPLY);
    }

    // ------------------------------------------------------------------------
    // Views (EIP-20)
    // ------------------------------------------------------------------------

    /// @notice Returns the token name.
    function name() external pure returns (string memory) {
        return NAME;
    }

    /// @notice Returns the token symbol.
    function symbol() external pure returns (string memory) {
        return SYMBOL;
    }

    /// @notice Returns the number of decimals.
    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    /// @notice Returns the total supply. It is fixed at deployment and never changes.
    function totalSupply() external pure returns (uint256) {
        return TOTAL_SUPPLY;
    }

    /// @notice Returns the balance of `account`.
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /// @notice Returns how much `spender` may still move from `owner` through `transferFrom`.
    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    // ------------------------------------------------------------------------
    // Mutations (EIP-20)
    // ------------------------------------------------------------------------

    /// @notice Moves `value` tokens from the caller to `to`.
    /// @dev Reverts with `InvalidReceiver` for the zero address and `InsufficientBalance` when short.
    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /// @notice Lets `spender` move up to `value` of the caller's tokens through `transferFrom`.
    /// @dev Overwrites any previous allowance. See the README on the allowance front-running caveat.
    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    /// @notice Moves `value` tokens from `from` to `to` using the caller's allowance from `from`.
    /// @dev Only the caller's own allowance is spent. An allowance of `type(uint256).max` is treated
    ///      as unlimited and is not decremented.
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        _spendAllowance(from, msg.sender, value);
        _transfer(from, to, value);
        return true;
    }

    // ------------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------------

    function _transfer(address from, address to, uint256 value) private {
        if (from == address(0)) revert InvalidSender(address(0));
        if (to == address(0)) revert InvalidReceiver(address(0));

        uint256 fromBalance = _balances[from];
        if (fromBalance < value) revert InsufficientBalance(from, fromBalance, value);

        unchecked {
            // Cannot underflow: checked above. Cannot overflow: the sum of all balances is TOTAL_SUPPLY.
            _balances[from] = fromBalance - value;
            _balances[to] += value;
        }

        emit Transfer(from, to, value);
    }

    function _approve(address owner, address spender, uint256 value) private {
        if (owner == address(0)) revert InvalidApprover(address(0));
        if (spender == address(0)) revert InvalidSpender(address(0));
        _allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _spendAllowance(address owner, address spender, uint256 value) private {
        uint256 current = _allowances[owner][spender];
        if (current == type(uint256).max) return;
        if (current < value) revert InsufficientAllowance(spender, current, value);
        unchecked {
            _allowances[owner][spender] = current - value;
        }
    }
}
