// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Capped} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title ERC3009Token
/// @notice An ERC20 token with EIP-3009 (Transfer With Authorization) functionality
contract ERC3009Token is ERC20, ERC20Burnable, ERC20Capped, AccessControl, EIP712 {
    // --- EIP-3009 specific errors ---
    error AuthorizationStateInvalid(address authorizer, bytes32 nonce); // used or canceled
    error AuthorizationExpired(uint256 nowTime, uint256 validBefore);
    error AuthorizationNotYetValid(uint256 nowTime, uint256 validAfter);
    error InvalidSigner(address signer, address expected);
    error InvalidRecipient(address to);

    // --- EIP-3009 events ---
    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);
    event AuthorizationCanceled(address indexed authorizer, bytes32 indexed nonce);

    // --- EIP-3009 typehashes (per spec) ---
    bytes32 private constant _TRANSFER_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

    bytes32 private constant _RECEIVE_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

    bytes32 private constant _CANCEL_AUTHORIZATION_TYPEHASH =
        keccak256("CancelAuthorization(address authorizer,bytes32 nonce)");

    // --- EIP-3009 authorization state tracking ---
    // 0 = Unused, 1 = Used, 2 = Canceled
    mapping(address => mapping(bytes32 => uint8)) private _authorizationStates;

    // --- Role definitions ---
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // Decimals
    uint8 private immutable _decimals;

    /// @notice Constructor for ERC3009Token
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param __cap The maximum supply cap for the token
    /// @param __decimals The number of decimals for the token
    // @param initialSupply The initial supply of tokens
    // @param admin The address that will have admin and minter roles
    constructor(
        string memory name,
        string memory symbol,
        uint256 __cap,
        uint8 __decimals
        // uint256 initialSupply
        // address admin
    ) ERC20(name, symbol) ERC20Capped(__cap) EIP712(name, "1") {
        _decimals = __decimals;
        _mint(address(this), __cap);

        // _grantRole(MINTER_ROLE, admin);
        // 
        // if (initialSupply > 0) {
        //     require(initialSupply <= __cap, "ERC20Capped: cap exceeded");
        //     _mint(admin, initialSupply);
        // }
    }

    // -------------------------
    // EIP-3009 public interface
    // -------------------------

    /// @notice EIP-712 domain separator (for compatibility with offchain tooling)
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    // /// @notice Mint new tokens
    // /// @param to The address to mint tokens to
    // /// @param amount The amount of tokens to mint
    // function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
    //     _mint(to, amount);
    // }

    /// @notice Override _update to handle capped token transfers
    /// @param from The sender address
    /// @param to The recipient address
    /// @param value The amount of tokens to transfer
    function _update(address from, address to, uint256 value) internal virtual override(ERC20, ERC20Capped) {
        super._update(from, to, value);
    }

    /// @notice Returns the number of decimals used by the token
    /// @return The number of decimals
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /// @notice Returns authorization state for a given authorizer & nonce.
    /// true = Used or Canceled, false = Unused
    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool) {
        return _authorizationStates[authorizer][nonce] != 0;
    }

    /// @notice Execute an ERC20 transfer signed by `from`.
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bool) {
        _validateTimeframe(validAfter, validBefore);
        _useAuthorization(from, nonce);

        bytes32 structHash = keccak256(
            abi.encode(_TRANSFER_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce)
        );
        _requireValidSignature(from, structHash, v, r, s);

        _transfer(from, to, value);
        return true;
    }

    /// @notice Execute a transfer to the caller, preventing front-running.
    /// `to` MUST equal msg.sender per EIP-3009 best-practice.
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bool) {
        if (to != msg.sender) revert InvalidRecipient(to);

        _validateTimeframe(validAfter, validBefore);
        _useAuthorization(from, nonce);

        bytes32 structHash = keccak256(
            abi.encode(_RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce)
        );
        _requireValidSignature(from, structHash, v, r, s);

        _transfer(from, to, value);
        return true;
    }

    /// @notice Cancel a previously issued authorization (that hasn't been used yet).
    function cancelAuthorization(address authorizer, bytes32 nonce, uint8 v, bytes32 r, bytes32 s) external {
        // must be unused
        if (_authorizationStates[authorizer][nonce] != 0) {
            revert AuthorizationStateInvalid(authorizer, nonce);
        }

        bytes32 structHash = keccak256(abi.encode(_CANCEL_AUTHORIZATION_TYPEHASH, authorizer, nonce));
        _requireValidSignature(authorizer, structHash, v, r, s);

        _authorizationStates[authorizer][nonce] = 2; // Canceled
        emit AuthorizationCanceled(authorizer, nonce);
    }

    // -------------------------
    // Internal helpers (EIP-3009)
    // -------------------------

    function _validateTimeframe(uint256 validAfter, uint256 validBefore) internal view {
        uint256 nowTs = block.timestamp;
        if (nowTs <= validAfter) revert AuthorizationNotYetValid(nowTs, validAfter);
        if (nowTs >= validBefore) revert AuthorizationExpired(nowTs, validBefore);
    }

    function _useAuthorization(address authorizer, bytes32 nonce) internal {
        // must be unused
        if (_authorizationStates[authorizer][nonce] != 0) {
            revert AuthorizationStateInvalid(authorizer, nonce);
        }
        _authorizationStates[authorizer][nonce] = 1; // Used
        emit AuthorizationUsed(authorizer, nonce);
    }

    function _requireValidSignature(address expectedSigner, bytes32 structHash, uint8 v, bytes32 r, bytes32 s)
        internal
        view
    {
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, v, r, s);
        if (signer != expectedSigner) revert InvalidSigner(signer, expectedSigner);
    }
}