// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "../../src/echo/contracts/interfaces/IDiamondCut.sol";
import "../../src/echo/contracts/facets/DiamondCutFacet.sol";
import "../../src/echo/contracts/facets/DiamondLoupeFacet.sol";
import "../../src/echo/contracts/facets/OwnershipFacet.sol";
import "../../src/echo/contracts/facets/AccessControlFacet.sol";
import "../../src/echo/contracts/facets/CommonFunctionsFacet.sol";
import "../../src/echo/contracts/facets/DataGatheringFacet.sol";
import "../../src/echo/contracts/facets/GroupManagerFacet.sol";
import "../../src/echo/contracts/facets/RegistryFacet.sol";
import "../../src/echo/contracts/upgradeInitializers/DiamondInit.sol";
import "../../src/echo/contracts/Diamond.sol";

import "../../src/echo/contracts/interfaces/IIngesterDataGathering.sol";
import "../../src/echo/contracts/interfaces/IIngesterGroupManager.sol";
import "../../src/echo/contracts/interfaces/IIngesterRegistration.sol";

import "forge-std/console.sol";
import "forge-std/Test.sol";

import "./TestStates.sol";
import "../utils/Utils.sol";

// Import OpenZeppelin's Strings library
import "@openzeppelin/contracts/utils/Strings.sol";


contract TestGroups is StateAllFacetsNoReplication, TestingInvariants {
    string message = "test";
    uint256 nonce = 999;

    function setUp() public virtual override(StateAllFacetsNoReplication, StateDeployDiamondBase) {
        StateAllFacetsNoReplication.setUp();
    }

    function testAddGroup() public {
        groupManagerF.addGroup("group1");
        IIngesterGroupManager.GroupWithIngesters memory group = groupManagerF.getGroup("group1");
        assertTrue(group.isAdded);

        assertAllInvariants();
    }

    function testRemoveGroup() public {
        groupManagerF.addGroup("group1");
        groupManagerF.removeGroup("group1");
        vm.expectRevert(bytes('Group does not exist.'));
        groupManagerF.getGroup("group1");

        assertAllInvariants();
    }


    function testAddAndRemoveAllGroups() public {
        for (uint i = 0; i < 10; i++) {
            string memory groupName = string(abi.encodePacked("group", Strings.toString(i)));
            groupManagerF.addGroup(groupName);
        }

        for (uint i = 0; i < 10; i++) {
            string memory groupName = string(abi.encodePacked("group", Strings.toString(i)));
            groupManagerF.removeGroup(groupName);
        }
     
        assertAllInvariants();
    }

    function testAddAndRemoveRandomGroups() public {
        uint256 randomNumber = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty)))%50;
        
        for (uint i = 0; i < randomNumber; i++) {
            string memory groupName = string(abi.encodePacked("group", Strings.toString(i)));
            groupManagerF.addGroup(groupName);
        }

        for (uint i = 0; i < randomNumber; i++) {
            string memory groupName = string(abi.encodePacked("group", Strings.toString(i)));
            groupManagerF.removeGroup(groupName);
        }
        
        assertAllInvariants();
    }


    function testCreateNewClusters() public {
        uint256 maxClusterSize = groupManagerF.getMaxClusterSize();
        uint256 amountOfGroups = maxClusterSize * 3;

        for (uint i = 0; i < amountOfGroups; i++) {
            string memory groupName = string(abi.encodePacked("group", Strings.toString(i)));
            groupManagerF.addGroup(groupName);
        }
        uint256[] memory clusters = groupManagerF.getClusters();
        assertEq(clusters.length, 3);
        assertAllInvariants();
    }

    //function to add groups to create 3 clusters and then add 3 ingesters and check that the groups were properly distributed 
    function testGroupDistributionToIngesters() public {
        
        uint256 maxClusterSize = groupManagerF.getMaxClusterSize();
        uint256 amountOfGroups = maxClusterSize * 3;

        for (uint i = 0; i < amountOfGroups; i++) {
            string memory groupName = string(abi.encodePacked("group", Strings.toString(i)));
            groupManagerF.addGroup(groupName);
        }

        for (uint i = 1; i < 4; i++) {
            bytes32 messageHash = keccak256(abi.encodePacked(users[i], message, nonce));
            bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(users_priv_key[i-1]), ethSignedMessageHash);
            bytes memory signature = abi.encodePacked(r, s, v);
            assertEq(signature.length, 65);

            vm.startPrank(users[i-1]);
            registryF.registerIngester(users[i], message, nonce, signature);
            vm.stopPrank();
            bool isIngester = registryF.isRegisteredIngester(users[i]);
            bool isController = registryF.isRegisteredController(users[i-1]);
            assertTrue(isIngester);
            assertTrue(isController);
            IIngesterRegistration.IngesterWithGroups memory ingester = registryF.getIngesterWithGroups(users[i]);
            assertEq(ingester.assignedGroups.length, maxClusterSize);
        }

        assertAllInvariants();
    }

}

contract TestGroupsWithReplication is StateAddAllFacetsWithReplication, TestingInvariants {
    string message = "test";
    uint256 nonce = 999;

    function setUp() public virtual override(StateAddAllFacetsWithReplication, StateDeployDiamondBase) {
        StateAddAllFacetsWithReplication.setUp();
    }
    

    function testAddGroupsWithReplication() public {
        uint256 maxClusterSize = groupManagerF.getMaxClusterSize();
        uint256 numClusters = registryF.getClusterCount();
        uint256 numIngesters = numClusters * newMaxIngesterPerGroup;

        for (uint256 i = 1; i <= numIngesters; i++) {
            bytes memory signature = hashAndSignMessage(users[i], users_priv_key[i-1], message, nonce);

            vm.startPrank(users[i-1]);
            registryF.registerIngester(users[i], message, nonce, signature);
            vm.stopPrank();

            bool isIngester = registryF.isRegisteredIngester(users[i]);
            bool isController = registryF.isRegisteredController(users[i-1]);

            assertTrue(isIngester);
            assertTrue(isController);
            IIngesterRegistration.IngesterWithGroups memory ingester = registryF.getIngesterWithGroups(users[i]);
            assertEq(ingester.assignedGroups.length, maxClusterSize);
            
            uint256 clusterId = ingester.clusterId;
            IIngesterGroupManager.GroupsCluster memory cluster = registryF.getCluster(clusterId);

            assert(utils.contains(cluster.ingesterAddresses, users[i]));
        }
        
        assertAllInvariants();
    }

    function hashAndSignMessage(address user, bytes32 user_priv_key, string memory message, uint256 nonce) public returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encodePacked(user, message, nonce));
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(user_priv_key), ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65);

        return signature;
    }


}