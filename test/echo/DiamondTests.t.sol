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

    function testAddGroup(string memory groupUsername) public {
        vm.assume(bytes(groupUsername).length != 0);
        groupManagerF.addGroup(groupUsername);
        IIngesterGroupManager.GroupWithIngesters memory group = groupManagerF.getGroup(groupUsername);
        assertTrue(group.isAdded);

        assertAllInvariants();
    }


    function testRemoveGroup(string memory groupUsername) public {
        vm.assume(bytes(groupUsername).length != 0);
        groupManagerF.addGroup(groupUsername);
        groupManagerF.removeGroup(groupUsername);
        vm.expectRevert(bytes('Group does not exist.'));
        groupManagerF.getGroup(groupUsername);

        assertAllInvariants();
    }


    function testAddAndRemoveAllGroups(uint256 numGroups) public {
        vm.assume(numGroups > 0);
        vm.assume(numGroups < 200);
        for (uint i = 0; i < numGroups; i++) {
            string memory groupName = string(abi.encodePacked("group", Strings.toString(i)));
            groupManagerF.addGroup(groupName);
        }

        for (uint i = 0; i < numGroups; i++) {
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
    uint256 maxGroups = 500;

    function setUp() public virtual override(StateAddAllFacetsWithReplication, StateDeployDiamondBase) {
        StateAddAllFacetsWithReplication.setUp();
    }

    function addGroups(uint256 amountOfGroups) public {
        vm.assume(amountOfGroups > 0);
        vm.assume(amountOfGroups < maxGroups);

        for (uint i = 0; i < amountOfGroups; i++) {
            string memory groupName = string(abi.encodePacked("group", Strings.toString(i)));
            groupManagerF.addGroup(groupName);
        }
    }

    function removeGroups(uint256 amountOfGroups) public {
        vm.assume(amountOfGroups > 0);
        vm.assume(amountOfGroups < maxGroups);

        for (uint i = 0; i < amountOfGroups; i++) {
            string memory groupName = string(abi.encodePacked("group", Strings.toString(i)));
            IIngesterGroupManager.GroupWithIngesters memory groupToRemove = groupManagerF.getGroup(groupName);
            address[] memory groupIngesters = groupToRemove.ingesterAddresses;
            groupManagerF.removeGroup(groupName);
        
            for (uint256 i = 0; i < groupIngesters.length; i++) {
                IIngesterRegistration.IngesterWithGroups memory ingester = registryF.getIngesterWithGroups(groupIngesters[i]);
                assert(!utils.containsStr(ingester.assignedGroups, groupName));
            }
        }

    }


    function hashAndSignMessage(address user, bytes32 user_priv_key, string memory message, uint256 nonce) public returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encodePacked(user, message, nonce));
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(user_priv_key), ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        assertEq(signature.length, 65);

        return signature;
    }

    function registerIngesters(uint256 numIngesters) public {
        for (uint256 i = 1; i <= numIngesters; i++) {
            bytes memory signature = hashAndSignMessage(users[i], users_priv_key[i-1], message, nonce);

            vm.startPrank(users[i-1]);
            registryF.registerIngester(users[i], message, nonce, signature);
            vm.stopPrank();
        }
    }

    function registerIngester(uint256 userInd, uint256 controllerInd) public {
        address user = users[userInd];
        bytes32 users_priv_key = users_priv_key[controllerInd];
        address controller = users[userInd - 1];
        bytes memory signature = hashAndSignMessage(user, users_priv_key, message, nonce);

        vm.startPrank(controller);
        registryF.registerIngester(user, message, nonce, signature);
        vm.stopPrank();
    }

    function unRegisterIngester(address user, address controller) public {
        vm.startPrank(controller);
        registryF.unRegisterIngester(user);
        vm.stopPrank();
    }

    function unRegisterIngesters(uint256 numIngesters) public {
        vm.assume(numIngesters > 0);
        vm.assume(numIngesters < maxUsers);
        for (uint256 i = 1; i <= numIngesters; i++) {
            unRegisterIngester(users[i], users[i-1]);
        }
    }

    function testAddingAndRemoveAllGroupsWithReplication(uint256 numGroups) public {
        vm.assume(numGroups > 0);
        vm.assume(numGroups < maxGroups);

        addGroups(numGroups);
        removeGroups(numGroups);
     
        assertAllInvariants();
    }

    function testAddIngestersWithReplication(uint256 numIngesters, uint256 numGroups) public {
        vm.assume(numIngesters > 0);
        vm.assume(numIngesters < maxUsers);
        vm.assume(numGroups > 0);
        vm.assume(numGroups < maxGroups);

        addGroups(numGroups);

        uint256 maxClusterSize = groupManagerF.getMaxClusterSize();
        uint256 numClusters = registryF.getClusterCount();

        for (uint256 i = 1; i <= numIngesters; i++) {
            registerIngester(i, i-1);

            bool isIngester = registryF.isRegisteredIngester(users[i]);
            bool isController = registryF.isRegisteredController(users[i-1]);

            assertTrue(isIngester);
            assertTrue(isController);
            IIngesterRegistration.IngesterWithGroups memory ingester = registryF.getIngesterWithGroups(users[i]);
            assertLe(ingester.assignedGroups.length, maxClusterSize);
            
            uint256 clusterId = ingester.clusterId;
            IIngesterGroupManager.GroupsCluster memory cluster = registryF.getCluster(clusterId);
            
            address[] memory unallocatedIngesters = registryF.getunallocatedIngesters();
            bool isUnallocated = false;
            if (unallocatedIngesters.length > 0) {
                for (uint256 j = 0; j < unallocatedIngesters.length; j++) {
                    if (unallocatedIngesters[j] == users[i]){
                        isUnallocated = true;
                    }
                }
            }

            if (!isUnallocated) {
                assert(utils.containsAddr(cluster.ingesterAddresses, users[i]));
            }
        }
        
        assertAllInvariants();
    }

    function testAddAndRemoveIngestersWithReplication(uint256 numIngesters, uint256 numGroups) public {
        vm.assume(numIngesters > 0);
        vm.assume(numIngesters < maxUsers);
        vm.assume(numGroups > 0);
        vm.assume(numGroups < maxGroups);

        addGroups(numGroups);

        for (uint256 i = 1; i <= numIngesters; i++) {
            bytes memory signature = hashAndSignMessage(users[i], users_priv_key[i-1], message, nonce);

            vm.startPrank(users[i-1]);
            registryF.registerIngester(users[i], message, nonce, signature);
            vm.stopPrank();

        }
        unRegisterIngesters(numIngesters);

    }

    function testRemovingAllIngestersFromClusterWReplication(uint256 numGroups) public {
        vm.assume(numGroups > 0);
        vm.assume(numGroups < maxGroups);
        addGroups(numGroups);

        uint256 numClusters = groupManagerF.getClusterCount();
        uint256 numIngesters = (numClusters - 1) * 3;
        vm.assume(numIngesters < maxUsers);

        uint256 clusterIdToRemove = 0;

        registerIngesters(numIngesters);

        IIngesterGroupManager.GroupsCluster memory clusterToEmpty = groupManagerF.getCluster(clusterIdToRemove);
        string[] memory groupsToRemove = clusterToEmpty.groupUsernames;
        address[] memory ingestersToRemove = clusterToEmpty.ingesterAddresses;

        for (uint256 i = 0; i < groupsToRemove.length; i++) {
            groupManagerF.removeGroup(groupsToRemove[i]);
        }

        uint256[] memory remainingClusters = groupManagerF.getActiveClusters();
        uint256 addressMatchCount = 0;
        for(uint256 i = 0; i < remainingClusters.length; i++) {
            IIngesterGroupManager.GroupsCluster memory cluster = groupManagerF.getCluster(remainingClusters[i]);
            addressMatchCount += utils.countMatchingAddresses(cluster.ingesterAddresses, ingestersToRemove);
        }
        assertEq(addressMatchCount, ingestersToRemove.length);

        assertAllInvariants();
    }




}