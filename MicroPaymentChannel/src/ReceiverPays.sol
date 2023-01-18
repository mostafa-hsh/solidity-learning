// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

contract ReceiverPays {
    // @note made it public for easier testing
    address public owner = msg.sender;

    // @note made it public for easier testing
    mapping(uint => bool) public usedNonces;

    constructor() payable {}

    function claimPayment(
        uint amount,
        uint nonce,
        bytes memory signature
    ) external {
        // @note added description for requirement
        require(!usedNonces[nonce], "Nonce used before.");
        usedNonces[nonce] = true;

        // this recreate the message that was signed on the client
        bytes32 message = prefixed(
            keccak256(abi.encodePacked(msg.sender, amount, nonce, this))
        );

        // @note added description for requirement
        require(recoverSigner(message, signature) == owner, "Signature is wrong.");

        payable(msg.sender).transfer(amount);
    }

    /// destroy the contract and reclaim the leftover funds.
    function shutdown() external {
        require(msg.sender == owner);
        selfdestruct(payable(msg.sender));
    }

    /// signature methods.
    function splitSignature(
        bytes memory sig
    ) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        require(sig.length == 65);

        assembly {
            // first 32 bytes, after the length prefix.
            r := mload(add(sig, 32))
            // second 32 bytes.
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes).
            v := byte(0, mload(add(sig, 96)))
        }

        return (v, r, s);
    }

    function recoverSigner(
        bytes32 message,
        bytes memory sig
    ) internal pure returns (address) {
        (uint8 v, bytes32 r, bytes32 s) = splitSignature(sig);

        return ecrecover(message, v, r, s);
    }

    /// build a prefixed hash to mimic the behavior of eth_sign.
    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
            );
    }
}
