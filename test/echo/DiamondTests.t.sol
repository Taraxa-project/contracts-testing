// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

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


contract TestAddFacet1 is StateAddAllFacets {

    function test5CanCallTest1FacetFunction() public {

         // try to call function on new Facet
        GroupManagerFacet(address(diamond)).addGroup("group1");
    }

}