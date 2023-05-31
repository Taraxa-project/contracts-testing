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

contract DiamondDeployer is StateDeployDiamond {

    function test1HasThreeFacets() public {
        assertEq(facetAddressList.length, 3);
    }

    function test2FacetsHaveCorrectSelectors() public {

        for (uint i = 0; i < facetAddressList.length; i++) {
            bytes4[] memory fromLoupeFacet = ILoupe.facetFunctionSelectors(facetAddressList[i]);
            bytes4[] memory fromGenSelectors =  generateSelectors(facetNames[i]);
            assertTrue(sameMembers(fromLoupeFacet, fromGenSelectors));
        }
    }
}


contract TestInvariants is StateAddAllFacets {

    uint256 public mappingNonce = 1;
    mapping (uint256 => mapping (address => bool)) public controllers;

    function clearControllers() internal {
        mappingNonce++;
    }

    function assertIngesterPerGroupInvariant() public {
        uint256 maxIngesterPerGroup = groupManagerF.getMaxIngestersPerGroup();
        uint256[] memory clusters = groupManagerF.getClusters();

        for (uint256 i = 0; i < clusters.length; i++) {
            IIngesterGroupManager.GroupsCluster memory cluster = groupManagerF.getCluster(clusters[i]);
            assertLe(cluster.ingesterAddresses.length, maxIngesterPerGroup);
        }
    }

    function assertMaxClusterSizeInvariant() public {
        uint256 maxClusterSize = groupManagerF.getMaxClusterSize();
        uint256[] memory clusters = groupManagerF.getClusters();

        for (uint256 i = 0; i < clusters.length; i++) {
            IIngesterGroupManager.GroupsCluster memory cluster = groupManagerF.getCluster(clusters[i]);
            assertLe(cluster.groupUsernames.length, maxClusterSize);
        }
    }

    function assertGroupCountInvariant() public {
        uint256 groupCount = groupManagerF.getGroupCount();
        uint256[] memory clusters = groupManagerF.getClusters();
        uint256 groupCountCheck = 0;

        for (uint256 i = 0; i < clusters.length; i++) {
            IIngesterGroupManager.GroupsCluster memory cluster = groupManagerF.getCluster(clusters[i]);
            groupCountCheck += cluster.groupUsernames.length;
        }
        assertEq(groupCountCheck, groupCount);
    }

    function assertIngesterCountInvariant() public {
        uint256 ingesterCount = groupManagerF.getIngesterCount();
        uint256[] memory clusters = groupManagerF.getClusters();
        uint256 ingesterCountCheck = 0;

        for (uint256 i = 0; i < clusters.length; i++) {
            IIngesterGroupManager.GroupsCluster memory cluster = groupManagerF.getCluster(clusters[i]);
            ingesterCountCheck += cluster.ingesterAddresses.length;
        }
        assertEq(ingesterCountCheck, ingesterCount);
    }

    function assertInactiveClusterCountInvariant() public {
        uint256[] memory inactiveClusters = groupManagerF.getinactiveClusters();
        uint256[] memory clusters = groupManagerF.getClusters();
        uint256 inactiveClusterCheck = 0;

        for (uint256 i = 0; i < clusters.length; i++) {
            IIngesterGroupManager.GroupsCluster memory cluster = groupManagerF.getCluster(clusters[i]);
            if (cluster.groupUsernames.length == 0) {
                inactiveClusterCheck += 1;
            }
        }
        assertEq(inactiveClusterCheck, inactiveClusters.length);
    }

    function assertUniqueControllerInClusterInvariant() public {
        uint256[] memory clusters = groupManagerF.getClusters();

        for (uint256 i = 0; i < clusters.length; i++) {
            IIngesterGroupManager.GroupsCluster memory cluster = groupManagerF.getCluster(clusters[i]);
            uint256 numIngesters = cluster.ingesterAddresses.length;

            for (uint j = 0; j < numIngesters; j++) {
                address controllerAddress = groupManagerF.getIngesterController(cluster.ingesterAddresses[j]);
                
                //if not false then there is a non-unique controller within cluster
                assertFalse(controllers[mappingNonce][controllerAddress]);
                controllers[mappingNonce][controllerAddress] = true;
            }
            ++mappingNonce;
        }
    }

    function testAddGroup() public {
        GroupManagerFacet(address(diamond)).addGroup("group1");
    }

}