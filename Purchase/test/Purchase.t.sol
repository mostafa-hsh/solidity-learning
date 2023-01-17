// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "../src/Purchase.sol";

contract PurchaseTest is Test {
    Purchase purchase;
    address seller;
    address buyer;

    event Aborted();
    event PurchaseConfirmed();
    event ItemReceived();
    event SellerRefunded();

    function setUp() external {
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        deal(buyer, 20 ether);
        deal(seller, 20 ether);

        vm.prank(seller);
        purchase = new Purchase{value: 4 ether}();
    }

    function testCannotSendOddEtherValueToConstructor() external {
        address tester = makeAddr("tester");
        deal(tester, 20 ether);
        Purchase p;
        vm.expectRevert(Purchase.ValueNotEven.selector);
        vm.prank(tester);
        p = new Purchase{value: 1 ether + 3}();
    }

    function testOnlySellerCanCallAbort(address other) external {
        vm.assume(other != seller);
        vm.expectRevert(Purchase.OnlySeller.selector);
        purchase.abort();
    }

    function testOnlyInCreatedStateCanCallAbort() external {
        vm.startPrank(seller);

        // check for `State.Inactive`
        purchase.changeState(Purchase.State.Inactive);
        vm.expectRevert(Purchase.InvalidState.selector);
        purchase.abort();

        // check for `State.Locked`
        purchase.changeState(Purchase.State.Locked);
        vm.expectRevert(Purchase.InvalidState.selector);
        purchase.abort();

        // check for `State.Release`
        purchase.changeState(Purchase.State.Release);
        vm.expectRevert(Purchase.InvalidState.selector);
        purchase.abort();

        vm.stopPrank();
    }

    function testAbort() external {
        vm.expectEmit(false, false, false, false);
        emit Aborted();

        uint sellerBalanceBefore = seller.balance;
        vm.prank(seller);
        purchase.abort();

        assertEq(sellerBalanceBefore + 4 ether, seller.balance);
        assertEq(uint(purchase.state()), uint(Purchase.State.Inactive));
    }

    // msg.value == (2 * purchase.value())
    function testCannotConfirmPurchaseIfValueIsNotCorrect(uint v) external {
        vm.assume(v != (2 * purchase.value()) && v <= 20 ether);

        // by default state is `Created`
        vm.expectRevert();
        vm.prank(buyer);
        purchase.confirmPurchase{value: v}();
    }

    function testOnlyInCreatedStateCanCallConfirmPurchase() external {
        vm.startPrank(buyer);

        // check for `State.Inactive`
        purchase.changeState(Purchase.State.Inactive);
        vm.expectRevert(Purchase.InvalidState.selector);
        purchase.confirmPurchase();

        // check for `State.Locked`
        purchase.changeState(Purchase.State.Locked);
        vm.expectRevert(Purchase.InvalidState.selector);
        purchase.confirmPurchase();

        // check for `State.Release`
        purchase.changeState(Purchase.State.Release);
        vm.expectRevert(Purchase.InvalidState.selector);
        purchase.confirmPurchase();

        vm.stopPrank();
    }

    function testConfirmPurchase() public {
        vm.expectEmit(false, false, false, false);
        emit PurchaseConfirmed();

        vm.prank(buyer);
        purchase.confirmPurchase{value: 4 ether}();

        assertEq(purchase.buyer(), buyer);
        assertEq(uint(purchase.state()), uint(Purchase.State.Locked));
    }

    function testOnlyBuyerCanCallConfirmReceived(address other) external {
        vm.assume(other != buyer);

        vm.prank(buyer);
        purchase.confirmPurchase{value: 4 ether}();

        vm.expectRevert(Purchase.OnlyBuyer.selector);
        vm.prank(other);
        purchase.confirmReceived();
    }

    function testOnlyInLockedStateCanCallConfirmReceived() external {
        vm.startPrank(buyer);
        // this will initialize the `purchase.buyer()` to `buyer`
        purchase.confirmPurchase{value: 4 ether}();

        // check for `State.Inactive`
        purchase.changeState(Purchase.State.Inactive);
        vm.expectRevert(Purchase.InvalidState.selector);
        purchase.confirmReceived();

        // check for `State.Created`
        purchase.changeState(Purchase.State.Created);
        vm.expectRevert(Purchase.InvalidState.selector);
        purchase.confirmReceived();

        // check for `State.Release`
        purchase.changeState(Purchase.State.Release);
        vm.expectRevert(Purchase.InvalidState.selector);
        purchase.confirmReceived();

        vm.stopPrank();
    }

    function testConfirmReceived() public {
        testConfirmPurchase();

        vm.expectEmit(false, false, false, false);
        emit ItemReceived();

        uint buyerBeforeBalance = buyer.balance;
        vm.prank(buyer);
        purchase.confirmReceived();

        assertEq(uint(purchase.state()), uint(Purchase.State.Release));
        assertEq(buyerBeforeBalance + 2 ether, buyer.balance);
    }

    function testOnlySellerCanCallRefundSeller(address other) external {
        vm.assume(other != seller);

        testConfirmReceived();

        vm.expectRevert(Purchase.OnlySeller.selector);
        vm.prank(other);
        purchase.refundSeller();
    }

    function testOnlyInReleaseStateCanCallRefundSeller() external {
        vm.startPrank(seller);
        // this will initialize the `purchase.buyer()` to `buyer`

        // check for `State.Inactive`
        purchase.changeState(Purchase.State.Inactive);
        vm.expectRevert(Purchase.InvalidState.selector);
        purchase.refundSeller();

        // check for `State.Created`
        purchase.changeState(Purchase.State.Created);
        vm.expectRevert(Purchase.InvalidState.selector);
        purchase.refundSeller();

        // check for `State.Locked`
        purchase.changeState(Purchase.State.Locked);
        vm.expectRevert(Purchase.InvalidState.selector);
        purchase.refundSeller();

        vm.stopPrank();
    }

    function testRefundSeller() external {
        testConfirmReceived();

        vm.expectEmit(false, false, false, false);
        emit SellerRefunded();

        uint sellerBeforeBalance = seller.balance;
        vm.prank(seller);
        purchase.refundSeller();

        assertEq(uint(purchase.state()), uint(Purchase.State.Inactive));
        assertEq(sellerBeforeBalance + 6 ether, seller.balance);
    }
}
