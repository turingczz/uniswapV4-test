// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Script } from "lib/forge-std/src/Script.sol";
import { console } from "forge-std/console.sol";
import { Test } from "lib/forge-std/src/Test.sol";
import { ERC3009Token } from "../src/ERC3009Token.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract TestERC3009Token is Script, Test {
    ERC3009Token public token;
    address public deployer;
    address public alice;
    address public bob;
    
    uint256 public constant TOKEN_CAP = 1_000_000 * 1e18;
    uint256 public constant INITIAL_SUPPLY = 100_000 * 1e18;
    uint8 public constant DECIMALS = 18;
    
    function run() external {
        // 设置测试账户
        deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        alice = address(0x1234567890123456789012345678901234567890);
        bob = address(0x2345678901234567890123456789012345678901);
        
        console.log("=== ERC3009Token Function Test Start ===");
        console.log("Deployer address:", deployer);
        console.log("Alice address:", alice);
        console.log("Bob address:", bob);
        
        // 部署合约
        console.log("\n1. Deploying ERC3009Token contract...");
        token = new ERC3009Token(
            "Test ERC3009 Token", 
            "TET3009", 
            TOKEN_CAP, 
            DECIMALS
        );
        console.log("Contract deployed successfully, address:", address(token));
        
        // Test basic ERC20 functionality
        testBasicERC20();
        
        // Test EIP-3009 functionality
        testEIP3009();
        
        // Test access control functionality
        testAccessControl();
        
        console.log("\n=== ERC3009Token Function Test Completed ===");
    }
    
    function testBasicERC20() internal {
        console.log("\n2. Testing basic ERC20 functionality...");
        
        // Test token information
        assertEq(token.name(), "Test ERC3009 Token");
        assertEq(token.symbol(), "TET3009");
        assertEq(token.decimals(), DECIMALS);
        assertEq(token.totalSupply(), TOKEN_CAP); // Contract mints cap to itself
        assertEq(token.balanceOf(address(token)), TOKEN_CAP); // All tokens are in contract
        console.log("Token information correct");
        
        // Test transfer - first transfer some tokens from contract to deployer
        vm.prank(address(token));
        token.transfer(deployer, 2000 * 1e18);
        
        // Then test transfer from deployer to alice
        vm.prank(deployer);
        token.transfer(alice, 1000 * 1e18);
        assertEq(token.balanceOf(alice), 1000 * 1e18);
        console.log("Transfer functionality normal");
        
        // Test cap - since mint function is commented out, we'll test transfer cap instead
        // The contract already has TOKEN_CAP minted to itself in constructor
        vm.prank(address(token));
        vm.expectRevert("ERC20Capped: cap exceeded");
        token.transfer(deployer, TOKEN_CAP + 1);
        console.log("Cap functionality normal");
    }
    
    function testEIP3009() internal {
        console.log("\n3. Testing EIP-3009 functionality...");
        
        // Prepare test data
        uint256 value = 500 * 1e18;
        uint256 validAfter = block.timestamp;
        uint256 validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256("test-nonce-1");
        
        // Generate signature
        (uint8 v, bytes32 r, bytes32 s) = generateSignature(
            alice, // from
            bob,   // to
            value,
            validAfter,
            validBefore,
            nonce
        );
        
        // Test transferWithAuthorization
        console.log("Testing transferWithAuthorization...");
        
        // First transfer some tokens to Alice
        vm.prank(deployer);
        token.transfer(alice, value);
        
        // Alice authorizes Bob to transfer
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
        
        assertEq(token.balanceOf(bob), value);
        assertTrue(token.authorizationState(alice, nonce));
        console.log("transferWithAuthorization functionality normal");
        
        // Test receiveWithAuthorization
        console.log("Testing receiveWithAuthorization...");
        
        bytes32 nonce2 = keccak256("test-nonce-2");
        (v, r, s) = generateSignature(
            alice,      // from
            bob,        // to (must equal msg.sender)
            100 * 1e18, // value
            validAfter,
            validBefore,
            nonce2
        );
        
        // Transfer tokens to Alice
        vm.prank(deployer);
        token.transfer(alice, 100 * 1e18);
        
        // Bob calls receiveWithAuthorization
        vm.prank(bob);
        token.receiveWithAuthorization(
            alice,      // from
            bob,        // to (must equal msg.sender)
            100 * 1e18, // value
            validAfter,
            validBefore,
            nonce2,
            v, r, s
        );
        
        assertEq(token.balanceOf(bob), value + 100 * 1e18);
        assertTrue(token.authorizationState(alice, nonce2));
        console.log("receiveWithAuthorization functionality normal");
        
        // Test cancelAuthorization
        console.log("Testing cancelAuthorization...");
        
        bytes32 nonce3 = keccak256("test-nonce-3");
        (v, r, s) = generateSignature(
            alice,      // authorizer
            address(0), // to (not needed)
            0,          // value (not needed)
            validAfter,
            validBefore,
            nonce3
        );
        
        // Alice cancels authorization
        vm.prank(alice);
        token.cancelAuthorization(alice, nonce3, v, r, s);
        
        assertTrue(token.authorizationState(alice, nonce3));
        console.log("cancelAuthorization functionality normal");
    }
    
    function testAccessControl() internal {
        console.log("\n4. Testing access control functionality...");
        
        // Since mint function is commented out, we'll test transfer functionality instead
        // The contract already has TOKEN_CAP minted to itself in constructor
        
        // Test that contract can transfer tokens
        uint256 transferAmount = 10_000 * 1e18;
        
        // Contract can transfer tokens
        vm.prank(address(token));
        token.transfer(deployer, transferAmount);
        assertEq(token.balanceOf(deployer), INITIAL_SUPPLY + transferAmount);
        console.log("Contract transfer functionality normal");
        
        // Test that non-contract addresses cannot transfer from contract
        vm.prank(alice);
        vm.expectRevert();
        token.transferFrom(address(token), alice, 1000 * 1e18);
        console.log("Non-contract access control normal");
    }
    
    function generateSignature(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        // Use Alice's private key to generate signature
        uint256 alicePrivateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
        
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"),
                from,
                to,
                value,
                validAfter,
                validBefore,
                nonce
            )
        );
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                structHash
            )
        );
        
        (v, r, s) = vm.sign(alicePrivateKey, digest);
    }
}

/* Test commands:
forge script script/TestERC3009Token.sol:TestERC3009Token --fork-url $RPC_URL -vvv

Or local testing: ******
forge test --match-test testERC3009Token -vvv
*/