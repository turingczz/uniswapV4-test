// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Test } from "lib/forge-std/src/Test.sol";
import { ERC3009Token } from "../src/ERC3009Token.sol";

contract ERC3009TokenTest is Test {
    ERC3009Token public token;
    address public owner;
    address public alice;
    address public bob;
    
    uint256 public constant TOKEN_CAP = 1_000_000 * 1e18;
    uint256 public constant INITIAL_SUPPLY = 100_000 * 1e18;
    uint8 public constant DECIMALS = 18;
    
    function setUp() public {
        // Use known addresses for testing
        owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // Known private key: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
        alice = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // Known private key: 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
        bob = makeAddr("bob");
        
        // Deploy contract
        token = new ERC3009Token(
            "Test ERC3009 Token", 
            "TET3009", 
            TOKEN_CAP, 
            DECIMALS
        );
    }
    
    function test_BasicERC20() public {
        // Test token information
        assertEq(token.name(), "Test ERC3009 Token");
        assertEq(token.symbol(), "TET3009");
        assertEq(token.decimals(), DECIMALS);
        assertEq(token.totalSupply(), TOKEN_CAP); // Contract mints cap to itself
        assertEq(token.balanceOf(address(token)), TOKEN_CAP); // All tokens are in contract
        
        // Test transfer - first transfer some tokens from contract to owner
        vm.prank(address(token));
        token.transfer(owner, 2000 * 1e18);
        
        // Then test transfer from owner to alice
        vm.prank(owner);
        token.transfer(alice, 1000 * 1e18);
        assertEq(token.balanceOf(alice), 1000 * 1e18);
        
        // Test cap - since mint function is commented out, we can't directly test cap exceeded
        // The cap is enforced during minting, but since mint is disabled, we'll skip this test
        // Instead, we'll verify that total supply equals the cap
        assertEq(token.totalSupply(), TOKEN_CAP);
    }
    
    function test_TransferWithAuthorization() public {
        // Prepare test data
        uint256 value = 500 * 1e18;
        uint256 validAfter = block.timestamp - 1; // Make sure it's in the past
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("test-nonce-1");
        
        // First transfer tokens from contract to owner
        vm.prank(address(token));
        token.transfer(owner, value * 2);
        
        // Transfer some tokens to Alice
        vm.prank(owner);
        token.transfer(alice, value);
        
        // Generate Alice's signature
        (uint8 v, bytes32 r, bytes32 s) = _signTransferWithAuthorization(
            alice, // from
            bob,   // to
            value,
            validAfter,
            validBefore,
            nonce
        );
        
        // Bob calls transferWithAuthorization
        vm.prank(bob);
        token.transferWithAuthorization(
            alice,      // from
            bob,        // to
            value,      // value
            validAfter, // validAfter
            validBefore, // validBefore
            nonce,      // nonce
            v, r, s     // signature
        );
        
        // Verify results
        assertEq(token.balanceOf(bob), value);
        assertTrue(token.authorizationState(alice, nonce));
        
        // Test reusing authorization
        vm.prank(bob);
        vm.expectRevert();
        token.transferWithAuthorization(
            alice, bob, value, validAfter, validBefore, nonce, v, r, s
        );
    }
    
    function test_ReceiveWithAuthorization() public {
        // Prepare test data
        uint256 value = 100 * 1e18;
        uint256 validAfter = block.timestamp - 1; // Make sure it's in the past
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("test-nonce-2");
        
        // First transfer tokens from contract to owner
        vm.prank(address(token));
        token.transfer(owner, value * 2);
        
        // Transfer tokens to Alice
        vm.prank(owner);
        token.transfer(alice, value);
        
        // Generate Alice's signature
        (uint8 v, bytes32 r, bytes32 s) = _signReceiveWithAuthorization(
            alice, // from
            bob,   // to (must equal msg.sender)
            value,
            validAfter,
            validBefore,
            nonce
        );
        
        // Bob calls receiveWithAuthorization
        vm.prank(bob);
        token.receiveWithAuthorization(
            alice,      // from
            bob,        // to (must equal msg.sender)
            value,      // value
            validAfter,
            validBefore,
            nonce,
            v, r, s
        );
        
        // Verify results
        assertEq(token.balanceOf(bob), value);
        assertTrue(token.authorizationState(alice, nonce));
        
        // Test when to address is not equal to msg.sender
        vm.prank(alice);
        vm.expectRevert();
        token.receiveWithAuthorization(
            alice, bob, value, validAfter, validBefore, nonce, v, r, s
        );
    }
    
    function test_CancelAuthorization() public {
        // Prepare test data
        bytes32 nonce = keccak256("test-nonce-3");
        uint256 validAfter = block.timestamp;
        uint256 validBefore = block.timestamp + 1 hours;
        
        // Generate signature for cancel authorization
        (uint8 v, bytes32 r, bytes32 s) = _signCancelAuthorization(alice, nonce);
        
        // Alice cancels authorization
        vm.prank(alice);
        token.cancelAuthorization(alice, nonce, v, r, s);
        
        // Verify authorization state
        assertTrue(token.authorizationState(alice, nonce));
        
        // Test duplicate cancellation
        vm.prank(alice);
        vm.expectRevert();
        token.cancelAuthorization(alice, nonce, v, r, s);
    }
    
    // function test_MinterRole() public {
    //     // Test minting permissions
    //     uint256 mintAmount = 10_000 * 1e18;
    //     
    //     // Owner can mint
    //     vm.prank(owner);
    //     token.mint(owner, mintAmount);
    //     assertEq(token.balanceOf(owner), INITIAL_SUPPLY + mintAmount);
    //     
    //     // Other accounts cannot mint
    //     vm.prank(alice);
    //     vm.expectRevert();
    //     token.mint(alice, 1000 * 1e18);
    // }
    
    function test_DomainSeparator() public {
        // Test domain separator
        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        assertTrue(domainSeparator != bytes32(0));
    }
    
    // Internal helper functions
    function _signTransferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) internal returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 typeHash = keccak256(
            "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
        );
        
        bytes32 structHash = keccak256(
            abi.encode(typeHash, from, to, value, validAfter, validBefore, nonce)
        );
        
        bytes32 digest = _hashTypedData(structHash);
        
        // Use the correct private key based on the from address
        uint256 privateKey;
        if (from == owner) {
            privateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        } else if (from == alice) {
            privateKey = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
        } else {
            revert("Unknown from address");
        }
        (v, r, s) = vm.sign(privateKey, digest);
    }
    
    function _signReceiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) internal returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 typeHash = keccak256(
            "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
        );
        
        bytes32 structHash = keccak256(
            abi.encode(typeHash, from, to, value, validAfter, validBefore, nonce)
        );
        
        bytes32 digest = _hashTypedData(structHash);
        
        // Use the correct private key based on the from address
        uint256 privateKey;
        if (from == owner) {
            privateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        } else if (from == alice) {
            privateKey = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
        } else {
            revert("Unknown from address");
        }
        (v, r, s) = vm.sign(privateKey, digest);
    }
    
    function _signCancelAuthorization(
        address authorizer,
        bytes32 nonce
    ) internal returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 typeHash = keccak256("CancelAuthorization(address authorizer,bytes32 nonce)");
        
        bytes32 structHash = keccak256(abi.encode(typeHash, authorizer, nonce));
        
        bytes32 digest = _hashTypedData(structHash);
        
        // Use the correct private key based on the authorizer address
        uint256 privateKey;
        if (authorizer == owner) {
            privateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        } else if (authorizer == alice) {
            privateKey = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
        } else {
            revert("Unknown authorizer address");
        }
        (v, r, s) = vm.sign(privateKey, digest);
    }
    
    function _hashTypedData(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
    }
}