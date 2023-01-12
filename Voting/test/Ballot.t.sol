// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Ballot.sol";

contract BallotTest is Test {
    using stdStorage for StdStorage;

    Ballot ballot;
    uint proposalsLength;

    function setUp() external {
        // https://github.com/willitscale/learning-solidity/blob/master/support/INVALID_IMPLICIT_CONVERSION_OF_ARRAYS.MD
        // https://github.com/ethereum/solidity/issues/11879
        // error:
        // Invalid implicit conversion from bytes32[4] memory to bytes32[] memory requested.
        // ballot = new Ballot([bytes32('proposal 1'), 'proposal 2', 'proposal 3', 'proposal 4']);

        proposalsLength = 4;
        bytes32[] memory pNames = new bytes32[](proposalsLength);
        pNames[0] = "proposal 1";
        pNames[1] = "proposal 2";
        pNames[2] = "proposal 3";
        pNames[3] = "proposal 4";

        ballot = new Ballot(pNames);
    }

    function testConstructor() external {
        address chairperson = ballot.chairperson();
        assertEq(chairperson, address(this));
        (uint weight, , , ) = ballot.voters(chairperson);
        assertEq(weight, 1);

        for (uint i = 0; i < 4; i++) {
            (bytes32 name_, uint voteCount_) = ballot.proposals(i);

            assertEq(
                name_,
                bytes32(abi.encodePacked("proposal ", uint8(i + 0x31)))
            );
            assertEq(voteCount_, 0);
        }
    }

    /*****************************************/
    /*            GiveRightToVote            */
    /*****************************************/
    function testGiveRightToVote(address voter_) external {
        vm.assume(voter_ != ballot.chairperson() && voter_ != address(0));

        ballot.giveRightToVote(voter_);
        (uint weight, , , ) = ballot.voters(voter_);

        assertEq(weight, 1);
    }

    function testOnlyChairpersonCanGiveRightToVote(address giver) external {
        vm.assume(giver != ballot.chairperson());

        vm.expectRevert("Only chairperson can give right to vote.");
        vm.prank(giver);
        ballot.giveRightToVote(address(1));
    }

    function testCannotGiveRightToAddressZero() external {
        vm.expectRevert("Can not give right to address zero");
        ballot.giveRightToVote(address(0));
    }

    function testCannotGiveRightToWhoAlreadyHaveRight(address voter_) external {
        if (voter_ != ballot.chairperson() && voter_ != address(0)) {
            ballot.giveRightToVote(voter_);
        }

        (uint weight, bool voted, , ) = ballot.voters(voter_);
        assertEq(weight, 1);
        assertEq(voted, false);

        vm.expectRevert("The voter already given right to vote.");
        ballot.giveRightToVote(voter_);
    }

    /*****************************************/
    /*                  vote                 */
    /*****************************************/
    function testChairpersonCanVote(uint p) external {
        vm.assume(p < proposalsLength);
        ballot.vote(p);

        (, bool voted_, , uint vote_) = ballot.voters(address(this));
        assertEq(voted_, true);
        assertEq(vote_, p);

        (, uint count_) = ballot.proposals(p);
        assertEq(count_, 1);
    }

    function testCannotVoteIfHaveNoRight(address noRightVoter) external {
        vm.assume(noRightVoter != ballot.chairperson());

        vm.expectRevert("Has no right to vote.");
        vm.prank(noRightVoter);
        ballot.vote(0);
    }

    function testVote(address voter_, uint p) external {
        vm.assume(voter_ != address(0) && p < proposalsLength);
        if (voter_ != ballot.chairperson()) {
            ballot.giveRightToVote(voter_);
        }

        vm.prank(voter_);
        ballot.vote(p);
        (, bool voted_, , uint vote_) = ballot.voters(voter_);
        assertEq(voted_, true);
        assertEq(vote_, p);

        (, uint count_) = ballot.proposals(p);
        assertEq(count_, 1);
    }

    function testVoteUpdatesProposalCount(uint p) external {
        vm.assume(p < proposalsLength);

        for (uint160 i = 1; i <= 50; i++) {
            address v = address(i);
            ballot.giveRightToVote(v);
            vm.prank(v);
            ballot.vote(p);
        }

        (, uint count) = ballot.proposals(p);
        assertEq(count, 50);
    }

    function testCannotVoteOutOfRangeProposal(uint p) external {
        vm.assume(p >= proposalsLength);

        // Will not work for empty arrays in external contracts.
        // For those, use `expectRevert` without any arguments.
        vm.expectRevert(stdError.indexOOBError);
        ballot.vote(p);
    }

    function testCannotVoteIfAlreadyVoted(address alreadyVoted) external {
        vm.assume(alreadyVoted != address(0));
        if (alreadyVoted != ballot.chairperson()) {
            ballot.giveRightToVote(alreadyVoted);
        }

        vm.prank(alreadyVoted);
        ballot.vote(0);

        vm.expectRevert("Already voted.");
        vm.prank(alreadyVoted);
        ballot.vote(0);
    }

    /*****************************************/
    /*                Delegate               */
    /*****************************************/
    function testChairpersonCanDelegate(address alice) external {
        vm.assume(alice != ballot.chairperson() && alice != address(0));
        ballot.giveRightToVote(alice);

        ballot.delegate(alice);

        (, , address chairpersonDelegate, ) = ballot.voters(
            ballot.chairperson()
        );
        assertEq(chairpersonDelegate, alice);
    }

    function testCannotDelegateIfHaveNoWeight(address noRight) external {
        address alice = address(0x323232);
        vm.assume(noRight != ballot.chairperson() && noRight != alice);

        vm.expectRevert("You have no right to vote.");
        vm.prank(noRight);
        ballot.delegate(alice);
    }

    function testCannotDelegateIfAlreadyVoted(address alreadyVoted) external {
        vm.assume(alreadyVoted != address(0));
        if (alreadyVoted != ballot.chairperson()) {
            ballot.giveRightToVote(alreadyVoted);
        }

        vm.prank(alreadyVoted);
        ballot.vote(0);

        vm.expectRevert("You already voted.");
        vm.prank(alreadyVoted);
        ballot.delegate(address(0x424242));

        // Foundry Limitation: Accessing packed slots is not supported
        // https://book.getfoundry.sh/reference/forge-std/std-storage
        // bool s = stdstore
        //     .target(address(ballot))
        //     .sig("voters(address)")
        //     .with_key(alreadyVoted)
        //     .depth(1)
        //     .read_bool();
        //
        // console.logBool(s);
    }

    function testCannotDelegateIfAlreadyDelegated(
        address alreadyDelegated
    ) external {
        address alice = address(0x123456789);
        vm.assume(alreadyDelegated != alice && alreadyDelegated != address(0));
        ballot.giveRightToVote(alice);

        if (alreadyDelegated != ballot.chairperson()) {
            ballot.giveRightToVote(alreadyDelegated);
        }

        vm.prank(alreadyDelegated);
        ballot.delegate(alice);

        vm.expectRevert("You already voted.");
        vm.prank(alreadyDelegated);
        ballot.delegate(alice);
    }

    function testCannotSelfDelegate(address voter_) external {
        vm.assume(voter_ != address(0));
        if (voter_ != ballot.chairperson()) {
            ballot.giveRightToVote(voter_);
        }

        vm.expectRevert("Self-delegation is disallowed.");
        vm.prank(voter_);
        ballot.delegate(voter_);
    }

    function testCannotDelegateToNoRightAccount(address noRight) external {
        address alice = address(0x32425262);
        vm.assume(noRight != ballot.chairperson() && noRight != alice && noRight != address(0));

        ballot.giveRightToVote(alice);

        vm.expectRevert("Voters cannot delegate to accounts that cannot vote.");
        vm.prank(alice);
        ballot.delegate(noRight);
    }

    function testDelegate(address voter_, address delegate_) external {
        vm.assume(voter_ != delegate_ && voter_ != address(0) && delegate_ != address(0));

        if (voter_ != ballot.chairperson()) {
            ballot.giveRightToVote(voter_);
        }
        if (delegate_ != ballot.chairperson()) {
            ballot.giveRightToVote(delegate_);
        }

        vm.prank(voter_);
        ballot.delegate(delegate_);

        (uint v_weight, bool v_voted, address v_delegate, uint v_vote) = ballot
            .voters(voter_);
        assertEq(v_weight, 1);
        assertEq(v_voted, true);
        assertEq(v_delegate, delegate_);
        assertEq(v_vote, 0);

        (uint d_weight, bool d_voted, address d_delegate, uint d_vote) = ballot
            .voters(delegate_);
        assertEq(d_weight, 2);
        assertEq(d_voted, false);
        assertEq(d_delegate, address(0));
        assertEq(d_vote, 0);
    }

    function testDelegateToAlreadyVoted(
        address voter_,
        address delegate_
    ) external {
        vm.assume(voter_ != delegate_ && voter_ != address(0) && delegate_ != address(0));

        if (voter_ != ballot.chairperson()) {
            ballot.giveRightToVote(voter_);
        }
        if (delegate_ != ballot.chairperson()) {
            ballot.giveRightToVote(delegate_);
        }

        // first delegate vote on a proposal
        vm.prank(delegate_);
        ballot.vote(1);
        (, , , uint v) = ballot.voters(delegate_);
        assertEq(v, 1);

        (, uint c) = ballot.proposals(1);
        assertEq(c, 1);

        vm.prank(voter_);
        ballot.delegate(delegate_);

        (uint v_weight, bool v_voted, address v_delegate, uint v_vote) = ballot
            .voters(voter_);
        assertEq(v_weight, 1);
        assertEq(v_voted, true);
        assertEq(v_delegate, delegate_);
        assertEq(v_vote, 0);

        (uint d_weight, bool d_voted, address d_delegate, uint d_vote) = ballot
            .voters(delegate_);
        assertEq(d_weight, 1);
        assertEq(d_voted, true);
        assertEq(d_delegate, address(0));
        assertEq(d_vote, 1);

        (, uint count) = ballot.proposals(1);
        assertEq(count, 2);
    }

    // voter -> alice -> bob -> voter
    function testCannotHaveLoopInDelegation() external {
        address alice = address(1);
        address bob = address(2);
        address voter_ = address(3);
        vm.assume(voter_ != alice && voter_ != bob && voter_ != address(0));

        ballot.giveRightToVote(alice);
        ballot.giveRightToVote(bob);

        if (voter_ != ballot.chairperson()) {
            ballot.giveRightToVote(voter_);
        }

        // voter -> alice -> bob -> voter
        // bob -> voter
        // alice -> bob
        // voter -> alice (revert happens here)

        // bob -> voter
        vm.prank(bob);
        ballot.delegate(voter_);
        (, bool b_voted_1, address b_delegate_1, ) = ballot.voters(bob);
        assertEq(b_voted_1, true);
        assertEq(b_delegate_1, voter_);
        (uint v_weight_1, , , ) = ballot.voters(voter_);
        assertEq(v_weight_1, 2);

        // alice -> bob
        vm.prank(alice);
        ballot.delegate(bob);
        (, bool a_voted, address a_delegate, ) = ballot.voters(alice);
        assertEq(a_voted, true);
        assertEq(a_delegate, voter_);

        // `weight` should be the same because `weight` added at the end of chain (voter)
        (uint b_weight_2, , , ) = ballot.voters(bob);
        assertEq(b_weight_2, 1);

        (uint v_weight_2, , , ) = ballot.voters(voter_);
        assertEq(v_weight_2, 3);

        // voter -> alice (revert happens here)
        vm.expectRevert("Found loop in delegation.");
        vm.prank(voter_);
        ballot.delegate(alice);
    }

    // john -> alice -> bob -> jafar
    function testDelegateChain() external {
        address john = address(0x111111111);
        address alice = address(0x222222222);
        address bob = address(0x333333333);
        address jafar = address(0x444444444);

        ballot.giveRightToVote(john);
        ballot.giveRightToVote(alice);
        ballot.giveRightToVote(bob);
        ballot.giveRightToVote(jafar);

        // bob -> jafar
        vm.prank(bob);
        ballot.delegate(jafar);

        // alice -> bob
        vm.prank(alice);
        ballot.delegate(bob);

        // john -> alice
        vm.prank(john);
        ballot.delegate(alice);

        // And jafar vote proposal 1
        vm.prank(jafar);
        ballot.vote(1);

        (uint j_w, , address j_d, ) = ballot.voters(john);
        assertEq(j_w, 1);
        assertEq(j_d, jafar);

        (uint a_w, , address a_d, ) = ballot.voters(alice);
        assertEq(a_w, 1);
        assertEq(a_d, jafar);

        (uint b_w, , address b_d, ) = ballot.voters(bob);
        assertEq(b_w, 1);
        assertEq(b_d, jafar);

        (uint jafar_w, bool jafar_v, address jafar_d, uint jafar_vote) = ballot
            .voters(jafar);
        assertEq(jafar_w, 4);
        assertEq(jafar_v, true);
        assertEq(jafar_d, address(0));
        assertEq(jafar_vote, 1);

        (, uint count) = ballot.proposals(1);
        assertEq(count, 4);
    }

    /*****************************************/
    /*                winnerName             */
    /*****************************************/
    function testWinnerName() external {
        uint snapshot = vm.snapshot();
        for (uint i = 0; i < proposalsLength; i++) {
            stdstore
                .target(address(ballot))
                .sig("proposals(uint256)")
                .with_key(i)
                .depth(1)
                .checked_write(i);
        }

        uint winningProposalId = ballot.winningProposal();
        assertEq(winningProposalId, 3);
        bytes32 winningProposalName = ballot.winnerName();
        assertEq(winningProposalName, "proposal 4");

        vm.revertTo(snapshot);

        uint x = 50;
        for (uint i = 0; i < proposalsLength; i++) {
            stdstore
                .target(address(ballot))
                .sig("proposals(uint256)")
                .with_key(i)
                .depth(1)
                .checked_write(x-i);
        }

        uint winningProposalId_1 = ballot.winningProposal();
        assertEq(winningProposalId_1, 0);
        bytes32 winningProposalName_1 = ballot.winnerName();
        assertEq(winningProposalName_1, "proposal 1");

    }
}
