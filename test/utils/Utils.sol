// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import {Test} from "forge-std/Test.sol";

contract Utils is Test {
    bytes32 internal nextUser = keccak256(abi.encodePacked("user address"));

    function getNextUserAddress() external returns (address payable) {
        address payable user = payable(address(uint160(uint256(nextUser))));
        nextUser = keccak256(abi.encodePacked(nextUser));
        return user;
    }

    function createPayableUsers(uint256 userNum)
        external
        returns (address payable[] memory)
    {
        address payable[] memory users = new address payable[](userNum);
        for (uint256 i = 0; i < userNum; i++) {
            address payable user = this.getNextUserAddress();
            vm.deal(user, 100 ether);
            users[i] = user;
        }

        return users;
    }

    function createUsers(uint256 userNum)
        external
        returns (address[] memory, bytes32[] memory)
    {
        address[] memory users = new address[](userNum);
        bytes32[] memory users_priv_key = new bytes32[](userNum);

        for (uint256 i = 0; i < userNum; i++) {
            // This will create a new address using `keccak256(i)` as the private key
            bytes32 privKey = keccak256(abi.encodePacked(i));
            address user = vm.addr(uint256(privKey));
            vm.deal(user, 100 ether);
            users[i] = user;
            users_priv_key[i] = privKey;
        }

        return (users, users_priv_key);
    }

    // move block.number forward by a given number of blocks
    function mineBlocks(uint256 numBlocks) external {
        uint256 targetBlock = block.number + numBlocks;
        vm.roll(targetBlock);
    }

    function containsAddr(address[] memory _array, address _value) public pure returns (bool) {
        for(uint i=0; i<_array.length; i++) {
            if(_array[i] == _value) {
                return true;
            }
        }
        return false;
    }

    function containsStr(string[] memory _array, string memory _value) public pure returns (bool) {
        for(uint i=0; i<_array.length; i++) {
            if(keccak256(abi.encodePacked(_array[i])) == keccak256(abi.encodePacked(_value))) {
                return true;
            }
        }
        return false;
    }

    function includesAddresses(address[] memory _array1, address[] memory _array2) public pure returns(bool) {
        for (uint i = 0; i < _array2.length; i++) {
            bool found = false;
            for (uint j = 0; j < _array1.length; j++) {
                if (_array1[j] == _array2[i]) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                return false;
            }
        }
        return true;
    }

    function countMatchingAddresses(address[] memory _array1, address[] memory _array2) public pure returns(uint256) {
        uint256 count = 0;
        for (uint i = 0; i < _array2.length; i++) {
            for (uint j = 0; j < _array1.length; j++) {
                if (_array1[j] == _array2[i]) {
                    count++;
                    break;
                }
            }
        }
        return count;
    }



}
