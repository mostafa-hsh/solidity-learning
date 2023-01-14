// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "../src/SimpleAuction.sol";

contract NoReceive {
    SimpleAuction auction;

    constructor(SimpleAuction auction_) {
        auction = auction_;
    }

    function bid() external payable {
        auction.bid{value: msg.value}();
    }

    function withdraw() external returns (bool) {
        bool succ = auction.withdraw();
        return succ;
    }
}

contract SimpleAuctionTest is Test {
    SimpleAuction auction;

    event HighestBidIncreased(address bidder, uint amount);
    event AuctionEnded(address winner, uint amount);

    function setUp() external {
        auction = new SimpleAuction(1 hours, payable(address(this)));
    }

    function testCannotBidAfterAuctionEnd() external {
        skip(2 hours);
        vm.expectRevert(SimpleAuction.AuctionAlreadyEnded.selector);
        auction.bid();
    }

    function testCannotBidIfValueIsZero() external {
        vm.expectRevert(
            abi.encodeWithSelector(SimpleAuction.BidNotHighEnough.selector, 0)
        );
        auction.bid();
    }

    function testBid() external {
        // first bid
        vm.expectEmit(false, false, false, true);
        emit HighestBidIncreased(address(this), 1 ether);
        auction.bid{value: 1 ether}();

        assertEq(auction.highestBidder(), address(this));
        assertEq(auction.highestBid(), 1 ether);

        // second bid
        address alice = makeAddr("alice");
        vm.expectEmit(false, false, false, true);
        emit HighestBidIncreased(address(alice), 2 ether);

        // Sets up a prank from an address that has some ether.
        hoax(alice);
        auction.bid{value: 2 ether}();

        assertEq(auction.highestBidder(), alice);
        assertEq(auction.highestBid(), 2 ether);
        assertEq(auction.pendingReturns(address(this)), 1 ether);

        // third bid but value is not greater than `highestBid`
        address bob = makeAddr("bob");
        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleAuction.BidNotHighEnough.selector,
                2 ether
            )
        );
        hoax(bob);
        auction.bid{value: 1.8 ether}();
    }

    function testWithdraw() external {
        // first bid
        auction.bid{value: 1 ether}();

        // second bid
        address john = makeAddr("john");
        hoax(john);
        uint johnBalance = john.balance;
        auction.bid{value: 2 ether}();

        // third bid
        NoReceive noReceive = new NoReceive(auction);
        noReceive.bid{value: 3 ether}();

        // forth bid
        address alice = makeAddr("alice");
        hoax(alice);
        auction.bid{value: 4 ether}();

        // first bid withdrawal (with receive function) (address(this))
        bool succ_1 = auction.withdraw();
        assertEq(succ_1, true);
        assertEq(auction.pendingReturns(address(this)), 0);

        // second bid withrawal (EOA account) (john)
        vm.prank(john);
        bool succ_2 = auction.withdraw();
        assertEq(succ_2, true);
        assertEq(johnBalance, john.balance);
        assertEq(auction.pendingReturns(john), 0);

        // third bid widthrawal unsuccessful (noReceive contract)
        // (because it has neither `receive` or `fallback` functions)
        vm.prank(address(noReceive));
        bool succ_3 = noReceive.withdraw();
        assertEq(succ_3, false);
        assertEq(address(noReceive).balance, 0);
        assertEq(auction.pendingReturns(address(noReceive)), 3 ether);
    }

    function testCannotCallAuctionEnd(uint elapse) external {
        vm.assume(elapse < 1 hours);
        skip(elapse);
        vm.expectRevert(SimpleAuction.AuctionNotYetEnded.selector);
        auction.auctionEnd();
    }

    function testAuctionEnd() external {
        address alice = makeAddr("alice");
        hoax(alice);
        auction.bid{value: 2 ether}();

        assertEq(auction.highestBid(), 2 ether);
        assertEq(address(auction).balance, 2 ether);
        skip(2 hours);

        vm.expectEmit(false, false, false, true);
        emit AuctionEnded(alice, 2 ether);
        auction.auctionEnd();

        assertEq(auction.ended(), true);
        assertEq(address(auction).balance, 0);
    }

    function testAuctionEndWithNoBid() external {
        assertEq(auction.highestBid(), 0);
        assertEq(auction.highestBidder(), address(0));

        skip(3 hours);

        vm.expectEmit(false, false, false, true);
        emit AuctionEnded(address(0), 0);
        auction.auctionEnd();

        assertEq(auction.ended(), true);
        assertEq(address(auction).balance, 0);
    }

    function testCannotActionEndIfAlreadyCalled() external {
        skip(4 hours);

        auction.auctionEnd();
        assertEq(auction.ended(), true);

        vm.expectRevert(SimpleAuction.AuctionEndAlreadyCalled.selector);
        auction.auctionEnd();
    }

    receive() external payable {}
}
