// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import "forge-std/Test.sol";
import "../src/SimplePaymentChannel.sol";

contract SimplePaymentChannelTest is Test {
    SimplePaymentChannel channel;
    address sender;
    uint senderKey;
    address recipient;
    uint expiration;

    function setUp() external {
        (sender, senderKey) = makeAddrAndKey("sender");
        recipient = makeAddr("recipient");
        deal(sender, 20 ether);
        deal(recipient, 10 ether);

        vm.prank(sender);
        channel = new SimplePaymentChannel{value: 10 ether}(
            payable(recipient),
            4 hours
        );

        expiration = block.timestamp + 4 hours;
        assertEq(channel.sender(), sender);
        assertEq(channel.recipient(), recipient);
        assertEq(channel.expiration(), expiration);
    }

    function testOnlySenderCanExtend(address other) external {
        vm.assume(other != sender);

        vm.expectRevert();
        vm.prank(other);
        channel.extend(expiration + 4 hours);
    }

    function testCannotExtendToEarlierTime(uint t) external {
        vm.assume(t <= expiration);

        vm.expectRevert();
        vm.prank(sender);
        channel.extend(t);
    }

    function testExtend(uint t) external {
        vm.assume(t > expiration);

        vm.prank(sender);
        channel.extend(t);
    }

    function testCannotClaimTimeoutEarlierThanExpiration(uint t) external {
        vm.assume(t < channel.expiration());

        vm.warp(t);
        vm.expectRevert();
        channel.claimTimeout();
    }

    function testClaimTimeout(uint t) external {
        vm.assume(t >= channel.expiration());
        vm.warp(t);
        channel.claimTimeout();
        assertEq(sender.balance, 20 ether);
    }

    function testOnlyRecipientCanCallClose(address other) external {
        vm.assume(other != recipient);

        vm.expectRevert();
        vm.prank(other);
        channel.close(0, abi.encodePacked(bytes32(0)));
    }

    function testCannotCloseWithInvalidSignature() external {
        // sign with `4 ether` but send `5 ether` as call input
        bytes memory message = abi.encodePacked(channel, uint(4 ether));
        bytes32 messageHash = prefixed(keccak256(message));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(senderKey, messageHash);

        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert();
        vm.prank(recipient);
        channel.close(5 ether, signature);
    }

    function testClose() external {
        bytes memory message = abi.encodePacked(channel, uint(5 ether));
        bytes32 messageHash = prefixed(keccak256(message));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(senderKey, messageHash);

        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(recipient);
        channel.close(5 ether, signature);

        assertEq(recipient.balance, 15 ether);
        assertEq(sender.balance, 15 ether);

        bytes32 messageHash2 = prefixed(
            keccak256(abi.encodePacked(channel, uint(5 ether)))
        );

        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(senderKey, messageHash2);
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);

        // @note currently there is no way to test that the contract correctly selfdestructed
        // in foundry and has a no bytecode
        // they are going to add a cheat code `vm.finalize`
        // that will be helpful for this scenario.
        // https://github.com/foundry-rs/foundry/issues/1543

        // revert by "EvmError: OutOfFund"
        vm.expectRevert();
        vm.prank(recipient);
        channel.close(5 ether, signature2);

        assertEq(recipient.balance, 15 ether);
        assertEq(sender.balance, 15 ether);
    }

    /// builds a prefixed hash to mimic the behavior of eth_sign.
    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("/x19Ethereum Signed Message:/n32", hash)
            );
    }
}
