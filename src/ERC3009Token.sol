// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Capped} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title ERC3009Token
/// @notice An ERC20 token with EIP-3009 (Transfer With Authorization) functionality
contract ERC3009Token is ERC20, ERC20Permit, ERC20Capped, ERC20Burnable, EIP712 {
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

    // Decimals
    uint8 private immutable _decimals;

    // --- EIP-3009 authorization state tracking ---
    // 0 = Unused, 1 = Used, 2 = Canceled
    mapping(address => mapping(bytes32 => uint8)) private _authorizationStates;

    /// @notice Constructor for ERC3009Token
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param to The address that will be mint to
    constructor(
        string memory name,
        string memory symbol,
        uint8 __decimals,
        uint256 __cap,
        address to
    ) ERC20(name, symbol) ERC20Permit(name) ERC20Capped(__cap) EIP712(name, "1") {
        _decimals = __decimals;
        if (__cap > 0) {
            _mint(to, __cap);
        }
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    // -------------------------
    // EIP-3009 public interface
    // -------------------------

    /// @notice EIP-712 domain separator (for compatibility with offchain tooling)
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
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