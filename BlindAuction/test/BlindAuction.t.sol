// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "../src/BlindAuction.sol";

contract BlindAuctionTest is Test {
    BlindAuction blind;
    address alice;
    address bob;
    address john;

    event AuctionEnded(address winner, uint highestBid);

    function setUp() external {
        john = makeAddr("john");
        vm.deal(john, 20 ether);

        blind = new BlindAuction(1 hours, 1 hours, payable(john));

        alice = makeAddr("alice");
        bob = makeAddr("bob");
        vm.deal(alice, 20 ether);
        vm.deal(bob, 20 ether);
    }

    function testBid(address bidder) external {
        bytes32 testHash = keccak256(
            abi.encodePacked(uint(2 ether), false, keccak256("secret"))
        );
        startHoax(bidder);

        for (uint i = 0; i < 5; i++) {
            blind.bid{value: 2 ether}(testHash);

            (bytes32 bidHash, uint bidValue) = blind.bids(bidder, i);
            assertEq(bidHash, testHash);
            assertEq(bidValue, 2 ether);
        }
    }

    function testCannotRevealBeforeBiddingEnd(uint t) external {
        vm.assume(t < 1 hours);
        uint[] memory v = new uint[](0);
        bool[] memory f = new bool[](0);
        bytes32[] memory b = new bytes32[](0);

        skip(t);
        vm.expectRevert(
            abi.encodePacked(BlindAuction.TooEarly.selector, blind.biddingEnd())
        );
        blind.reveal(v, f, b);
    }

    function testCannotRevealAfterRevealEnd(uint t) external {
        vm.assume(t > 2 hours && t < 10 hours);
        uint[] memory v = new uint[](0);
        bool[] memory f = new bool[](0);
        bytes32[] memory b = new bytes32[](0);

        skip(t);
        vm.expectRevert(
            abi.encodePacked(BlindAuction.TooLate.selector, blind.revealEnd())
        );
        blind.reveal(v, f, b);
    }

    function testCannotRevealIfInputLengthIsNotCorrect() external {
        vm.startPrank(alice);

        for (uint i = 0; i < 5; i++) {
            blind.bid(bytes32(0));
        }

        // incorrect `values` length
        uint[] memory v = new uint[](4);
        bool[] memory f = new bool[](5);
        bytes32[] memory b = new bytes32[](5);
        vm.expectRevert();
        blind.reveal(v, f, b);

        // incorrect `fakes` length
        v = new uint[](5);
        f = new bool[](2);
        vm.expectRevert();
        blind.reveal(v, f, b);

        // incorrect `secrets` length
        f = new bool[](5);
        b = new bytes32[](0);
        vm.expectRevert();
        blind.reveal(v, f, b);

        vm.stopPrank();
    }

    function testReveal() public {
        // stack too deep
        {
            // Alice bids
            bytes32 aliceBidHash1 = keccak256(
                abi.encodePacked(uint(1 ether), bool(false), bytes32("alice 1"))
            );
            bytes32 aliceBidHash2 = keccak256(
                abi.encodePacked(uint(2 ether), bool(true), bytes32("alice 2"))
            );
            bytes32 aliceBidHash3 = keccak256(
                abi.encodePacked(uint(3 ether), bool(false), bytes32("alice 3"))
            );

            vm.startPrank(alice);
            blind.bid{value: 1 ether}(aliceBidHash1);
            blind.bid{value: 2 ether}(aliceBidHash2);
            blind.bid{value: 3 ether}(aliceBidHash3);
            vm.stopPrank();
        }

        // stack too deep
        {
            // Bob bids
            bytes32 bobBidHash1 = keccak256(
                abi.encodePacked(uint(1.5 ether), false, bytes32("bob 1"))
            );
            bytes32 bobBidHash2 = keccak256(
                abi.encodePacked(uint(2.5 ether), false, bytes32("bob 2"))
            );
            // line 108 - value(3.1 ether) != deposited(3.5 ether)
            bytes32 bobBidHash3 = keccak256(
                abi.encodePacked(uint(3.1 ether), false, bytes32("bob 3"))
            );
            bytes32 bobBidHash4 = keccak256(
                abi.encodePacked(uint(4 ether), true, bytes32("bob 4"))
            );

            vm.startPrank(bob);
            blind.bid{value: 1.5 ether}(bobBidHash1);
            blind.bid{value: 2.5 ether}(bobBidHash2);
            blind.bid{value: 3.5 ether}(bobBidHash3); // value(3.1 ether) != deposited(3.5 ether)
            blind.bid{value: 4 ether}(bobBidHash4);
            vm.stopPrank();
        }

        // skip to reveal time
        skip(1.5 hours);

        // Alice tx data
        uint[] memory aValues = new uint[](3);
        bool[] memory aFakes = new bool[](3);
        bytes32[] memory aSecrets = new bytes32[](3);
        aValues[0] = uint(1 ether);
        aValues[1] = 2 ether;
        aValues[2] = 3 ether;
        aFakes[0] = false;
        aFakes[1] = true;
        aFakes[2] = false;
        aSecrets[0] = "alice 1";
        aSecrets[1] = "alice 2";
        aSecrets[2] = "alice 3";

        // Alice reveal
        // bid 1 -> highestBidder: alice --- highestBid: 1 ether
        // bid 2 -> fake == true -> refund = 2 ether
        // bid 3 -> highestBidder: alice --- highestBid: 3 ether
        //       -> pendingReturn[alice] = 1 ether
        uint aliceBalanceBeforeReveal = alice.balance;
        vm.prank(alice);
        blind.reveal(aValues, aFakes, aSecrets);

        assertEq(
            aliceBalanceBeforeReveal + 2 ether,
            alice.balance,
            "did not refunded"
        );
        assertEq(blind.highestBidder(), alice);
        assertEq(blind.highestBid(), 3 ether);
        assertEq(blind.pendingReturns(alice), 1 ether);

        // Bob tx data
        // Bob do not want to show the first bid
        uint[] memory bValues = new uint[](4);
        bool[] memory bFakes = new bool[](4);
        bytes32[] memory bSecrets = new bytes32[](4);
        bValues[0] = 1.5 ether;
        bValues[1] = 2.5 ether;
        bValues[2] = 3.1 ether; // value(3.1 ether) != deposited(3.5 ether)
        bValues[3] = 4 ether;
        bFakes[0] = false;
        bFakes[1] = false;
        bFakes[2] = false;
        bFakes[3] = true;
        bSecrets[0] = ""; // Wrong secret for not revealing first bid
        bSecrets[1] = "bob 2";
        bSecrets[2] = "bob 3";
        bSecrets[3] = "bob 4";

        // Bob reveal
        // bid 1 -> wrong secret -> does not reveal and no refund
        // bid 2 -> value(2.5 ether) < highestBid(3 ether) -> refund = 2.5 ether
        // bid 3 -> value(3.1 ether) >= highestBid(3 ether)
        //       -> highestBidder: bob --- highestBid: 3.1 ether
        //       -> value(3.1 ether) != deposited(3.5 ether) -> refund += 0.4 ether
        //       -> pendingReturns[alice] += 3 ether
        // bid 4 -> fake == true -> refund += 4 ether
        //
        // refund = 6.9 ether --- pendingReturns[alice] = 4 ether
        // highestBidder = bob --- highestBid = 3.1 ether
        uint bobBalanceBeforeReveal = bob.balance;
        vm.prank(bob);
        blind.reveal(bValues, bFakes, bSecrets);

        assertEq(
            bobBalanceBeforeReveal + 6.9 ether,
            bob.balance,
            "did not refunded"
        );
        assertEq(blind.highestBidder(), bob);
        assertEq(blind.highestBid(), 3.1 ether);
        assertEq(blind.pendingReturns(alice), 4 ether);
        assertEq(blind.pendingReturns(bob), 0);

        bSecrets[0] = "bob 1"; // make the secret right to refund it
        uint bobBalanceBeforeSecondReveal = bob.balance;
        vm.prank(bob);
        blind.reveal(bValues, bFakes, bSecrets);
        // bid 1 -> value(1.5 ether) < highestBid(3.1 ether) -> refund = 1.5 ether
        // bid 2,3,4 -> hash does not match so they have no effect

        assertEq(
            bobBalanceBeforeSecondReveal + 1.5 ether,
            bob.balance,
            "did not refunded"
        );
        assertEq(blind.highestBidder(), bob);
        assertEq(blind.highestBid(), 3.1 ether);
    }

    function testWithdraw() external {
        testReveal();

        uint pending = blind.pendingReturns(alice);
        assertEq(pending, 4 ether);

        uint beforeWithdrawBalance = alice.balance;
        vm.prank(alice);
        blind.withdraw();

        assertEq(beforeWithdrawBalance + 4 ether, alice.balance);
    }

    function testCannotEndAuctionBeforeRevealEnd(uint t) external {
        vm.assume(t < 2 hours);

        vm.expectRevert(
            abi.encodePacked(BlindAuction.TooEarly.selector, blind.revealEnd())
        );
        blind.auctionEnd();
    }

    function testCannotEndAuctionIfAlreadyEnded() external {
        // skip after reveal end
        skip(3 hours);

        blind.auctionEnd();
        assertEq(blind.ended(), true);

        vm.expectRevert(BlindAuction.AuctionEndAlreadyCalled.selector);
        blind.auctionEnd();
    }

    function testAuctionEnd() external {
        testReveal();

        // skip after reveal end
        skip(4 hours);

        uint balanceBefore = john.balance;

        vm.expectEmit(false, false, false, true);
        emit AuctionEnded(bob, 3.1 ether);

        blind.auctionEnd();

        assertEq(balanceBefore + 3.1 ether, john.balance);
    }
}
