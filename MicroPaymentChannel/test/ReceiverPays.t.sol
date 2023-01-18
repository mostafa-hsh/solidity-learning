// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import "forge-std/Test.sol";
import "../src/ReceiverPays.sol";

contract ReceiverPaysTest is Test {
    ReceiverPays rp;
    address owner;
    uint ownerKey;
    address recipient;

    function setUp() external {
        (owner, ownerKey) = makeAddrAndKey("owner");
        recipient = makeAddr("recipient");
        deal(owner, 20 ether);
        deal(recipient, 20 ether);

        vm.prank(owner);
        rp = new ReceiverPays{value: 10 ether}();
    }

    function testClaimPayment() public {
        // message format:
        // msg.sender: recipient,
        // amount: 2 ether,
        // nonce: 0,
        // address(rp)
        bytes32 messageHash = prefixed(
            keccak256(abi.encodePacked(recipient, uint(2 ether), uint(0), rp))
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, messageHash);

        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(recipient);
        rp.claimPayment(2 ether, 0, signature);
        assertEq(recipient.balance, 22 ether);

        // message format:
        // msg.sender: recipient,
        // amount: 4 ether,
        // nonce: 1,
        // address(rp)
        bytes32 messageHash2 = prefixed(
            keccak256(abi.encodePacked(recipient, uint(4 ether), uint(1), rp))
        );

        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(ownerKey, messageHash2);

        bytes memory signature1 = abi.encodePacked(r1, s1, v1);

        vm.prank(recipient);
        rp.claimPayment(4 ether, 1, signature1);
        assertEq(recipient.balance, 26 ether);
    }

    function testCannotClaimPaymentWithSameNoneTwice() external {
        // used nonce 0 and 1 in `testClaimPayment`
        testClaimPayment();

        // reuse nonce 0
        bytes32 messageHash = prefixed(
            keccak256(abi.encodePacked(recipient, uint(2 ether), uint(0), rp))
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, messageHash);

        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert("Nonce used before.");
        vm.prank(recipient);
        rp.claimPayment(2 ether, 0, signature);

        // reuse nonce 1
        bytes32 messageHash1 = prefixed(
            keccak256(abi.encodePacked(recipient, uint(4 ether), uint(1), rp))
        );

        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(ownerKey, messageHash1);

        bytes memory signature1 = abi.encodePacked(r1, s1, v1);

        vm.expectRevert("Nonce used before.");
        vm.prank(recipient);
        rp.claimPayment(4 ether, 1, signature1);
    }

    function testCannotClaimPaymentIfSignatureIsWrong() external {
        // use `2 ether` for signing but `4 ether` for sending the transaction
        bytes32 messageHash = prefixed(
            keccak256(abi.encodePacked(recipient, uint(2 ether), uint(0), rp))
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, messageHash);

        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert("Signature is wrong.");
        vm.prank(recipient);
        rp.claimPayment(4 ether, 0, signature);
    }

    // test cannot send more than balance of contract rp
    function testCannotClaimPaymentMoreThanBalance() external {
        bytes32 messageHash = prefixed(
            keccak256(abi.encodePacked(recipient, uint(11 ether), uint(0), rp))
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, messageHash);

        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert();
        vm.prank(recipient);
        rp.claimPayment(11 ether, 0, signature);
    }

    function testShutdown() public {
        uint ownerBalanceBefore = owner.balance;

        vm.prank(owner);
        rp.shutdown();

        assertEq(ownerBalanceBefore + 10 ether, owner.balance);
        // @note currently there is no way to test that the contract correctly selfdestructed
        // in foundry and has a no bytecode
        // they are going to add a cheat code `vm.finalize`
        // that will be helpful for this scenario.
        // https://github.com/foundry-rs/foundry/issues/1543
    }

    /// build a prefixed hash to mimic the behavior of eth_sign.
    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
            );
    }
}
