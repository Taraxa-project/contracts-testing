// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/******************************************************************************\
* Authors: Timo Neumann <timo@fyde.fi>, Rohan Sundar <rohan@fyde.fi>
* EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
* Abstract Contracts for the shared setup of the tests
/******************************************************************************/

import "../../src/echo/contracts/interfaces/IDiamondCut.sol";
import "../../src/echo/contracts/facets/DiamondCutFacet.sol";
import "../../src/echo/contracts/facets/DiamondLoupeFacet.sol";
import "../../src/echo/contracts/facets/OwnershipFacet.sol";
import "../../src/echo/contracts/facets/AccessControlFacet.sol";
import "../../src/echo/contracts/facets/CommonFunctionsFacet.sol";
import "../../src/echo/contracts/facets/DataGatheringFacet.sol";
import "../../src/echo/contracts/facets/GroupManagerFacet.sol";
import "../../src/echo/contracts/facets/RegistryFacet.sol";
import "../../src/echo/contracts/Diamond.sol";
import "./HelperContract.sol";


abstract contract StateDeployDiamond is HelperContract {

    //contract types of facets to be deployed
    Diamond diamond;
    DiamondCutFacet dCutFacet;
    DiamondLoupeFacet dLoupe;
    OwnershipFacet ownerF;
  

    //interfaces with Facet ABI connected to diamond address
    IDiamondLoupe ILoupe;
    IDiamondCut ICut;

    string[] facetNames;
    address[] facetAddressList;

    // deploys diamond and connects facets
    function setUp() public virtual {

        //deploy facets
        dCutFacet = new DiamondCutFacet();
        dLoupe = new DiamondLoupeFacet();
        ownerF = new OwnershipFacet();
        facetNames = ["DiamondCutFacet", "DiamondLoupeFacet", "OwnershipFacet"];

        // diamod arguments
        DiamondArgs memory _args = DiamondArgs({
        owner: address(this),
        init: address(0),
        initCalldata: " "
        });

        // FacetCut with CutFacet for initialisation
        FacetCut[] memory cut0 = new FacetCut[](1);
        cut0[0] = FacetCut ({
            facetAddress: address(dCutFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: generateSelectors("DiamondCutFacet")
        });


        // deploy diamond
        diamond = new Diamond(cut0, _args);

        //upgrade diamond with facets

        //build cut struct
        FacetCut[] memory cut = new FacetCut[](2);

        cut[0] = (
            FacetCut({
            facetAddress: address(dLoupe),
            action: FacetCutAction.Add,
            functionSelectors: generateSelectors("DiamondLoupeFacet")
            })
        );

        cut[1] = (
            FacetCut({
            facetAddress: address(ownerF),
            action: FacetCutAction.Add,
            functionSelectors: generateSelectors("OwnershipFacet")
            })
        );

        // initialise interfaces
        ILoupe = IDiamondLoupe(address(diamond));
        ICut = IDiamondCut(address(diamond));

        //upgrade diamond
        ICut.diamondCut(cut, address(0x0), "");

        // get all addresses
        facetAddressList = ILoupe.facetAddresses();
    }


}


// tests proper upgrade of diamond when adding a facet
abstract contract StateAddFacet1 is StateDeployDiamond{

    AccessControlFacet accessF;
    CommonFunctionsFacet commonFunctionsF;
    DataGatheringFacet dataF;
    GroupManagerFacet groupManagerF;
    RegistryFacet registryF;

    function setUp() public virtual override {
        super.setUp();
        //deploy Test1Facet
        accessF = new AccessControlFacet();
        commonFunctionsF = new CommonFunctionsFacet();
        dataF = new DataGatheringFacet();
        groupManagerF = new GroupManagerFacet();
        registryF = new RegistryFacet();

        // get functions selectors but remove first element (supportsInterface)
        // bytes4[] memory fromGenSelectors  = removeElement(uint(0), generateSelectors("Test1Facet"));
        // bytes4[] memory registryFacetSelectors  = removeElement(generateSelectors("AccessControlFacet"), generateSelectors("RegistryFacet"));

        bytes4[] memory  selectrosAccess  = generateSelectors("AccessControlFacet");
        console.log('from gen selectors length', selectrosAccess.length);
        bytes4[] memory selectorsRegistry  = generateSelectors("RegistryFacet");
        console.log('from gen selectors2 length', selectorsRegistry.length);

        bytes4[] memory fromGenSelectorsMod = removeElements(selectrosAccess, selectorsRegistry);
        console.log('from gen selectors after modification length', fromGenSelectorsMod.length);

        // array of functions to add
        FacetCut[] memory facetCut = new FacetCut[](5);
        facetCut[0] =
        FacetCut({
            facetAddress: address(accessF),
            action: FacetCutAction.Add,
            functionSelectors: fromGenSelectorsMod
        });

        // add functions to diamond
        ICut.diamondCut(facetCut, address(0x0), "");

    }

}