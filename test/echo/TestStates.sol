// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

/******************************************************************************\
* Authors: Timo Neumann <timo@fyde.fi>, Rohan Sundar <rohan@fyde.fi>
* EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
* Abstract Contracts for the shared setup of the tests
/******************************************************************************/

import "../../src/echo/contracts/upgradeInitializers/DiamondInit.sol";
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
import "../utils/Utils.sol";


abstract contract StateDeployDiamond is HelperContract {
    Utils internal utils;
    address payable[] internal users;

    struct Args{
        uint256 maxClusterSize;
        uint256 maxIngestersPerGroup;
    }

    address owner;
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
        //Define Users
        owner = address(this);
        utils = new Utils();
        users = utils.createUsers(10);


        //deploy facets
        dCutFacet = new DiamondCutFacet();
        dLoupe = new DiamondLoupeFacet();
        ownerF = new OwnershipFacet();
        DiamondInit dInit = new DiamondInit();

        facetNames = ["DiamondCutFacet", "DiamondLoupeFacet", "OwnershipFacet"];

        DiamondInit.Args memory initArgs = DiamondInit.Args({
            maxClusterSize: 500,
            maxIngestersPerGroup: 1
        });

        // Encode initArgs with the function signature
        bytes memory initCalldata = abi.encodeWithSignature("init(DiamondInit.Args)", initArgs);

        // Diamond arguments
        DiamondArgs memory _args = DiamondArgs({
            owner: address(this),
            init: address(0), // Replace with the actual address of the contract that has the `init` function
            initCalldata: initCalldata
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


abstract contract StateAddAllFacets is StateDeployDiamond{

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

        bytes4[] memory selectorsAccess  = generateSelectors("AccessControlFacet");
        bytes4[] memory selectorsCommon  = generateSelectors("CommonFunctionsFacet");
        bytes4[] memory selectorsData  = generateSelectors("DataGatheringFacet");
        bytes4[] memory selectorsGroups  = generateSelectors("GroupManagerFacet");
        bytes4[] memory selectorsRegistry  = generateSelectors("RegistryFacet");

        //remove shared functions from facets
        bytes4[] memory selectorsDataWAccess = removeElements(selectorsAccess, selectorsData);
        bytes4[] memory selectorsDataWShared = removeElements(selectorsCommon, selectorsDataWAccess);
        
        bytes4[] memory selectorsGroupsWAccess = removeElements(selectorsAccess, selectorsGroups);
        bytes4[] memory selectorsGroupsWShared = removeElements(selectorsCommon, selectorsGroupsWAccess);
        
        bytes4[] memory selectorsRegistryWAccess = removeElements(selectorsAccess, selectorsRegistry);
        bytes4[] memory selectorsRegistryWShared = removeElements(selectorsCommon, selectorsRegistryWAccess);
        


        // array of functions to add
        FacetCut[] memory facetCut = new FacetCut[](5);
        facetCut[0] =
        FacetCut({
            facetAddress: address(accessF),
            action: FacetCutAction.Add,
            functionSelectors: selectorsAccess
        });

        facetCut[1] =
        FacetCut({
            facetAddress: address(commonFunctionsF),
            action: FacetCutAction.Add,
            functionSelectors: selectorsCommon
        });

        facetCut[2] =
        FacetCut({
            facetAddress: address(dataF),
            action: FacetCutAction.Add,
            functionSelectors: selectorsDataWShared
        });

        facetCut[3] =
        FacetCut({
            facetAddress: address(groupManagerF),
            action: FacetCutAction.Add,
            functionSelectors: selectorsGroupsWShared
        });

        facetCut[4] =
        FacetCut({
            facetAddress: address(registryF),
            action: FacetCutAction.Add,
            functionSelectors: selectorsRegistryWShared
        });

        // add functions to diamond
        ICut.diamondCut(facetCut, address(0x0), "");

        accessF = AccessControlFacet(address(diamond));
        commonFunctionsF = CommonFunctionsFacet(address(diamond));
        dataF = DataGatheringFacet(address(diamond));
        groupManagerF = GroupManagerFacet(address(diamond));
        registryF = RegistryFacet(address(diamond));
        
        setNewMaxClusterSize(10);
        setNewMaxIngestersPerGroup(1);

    }

    function setNewMaxClusterSize(uint256 maxClusterSize) public {
        groupManagerF.setMaxClusterSize(maxClusterSize);
    }

    function setNewMaxIngestersPerGroup(uint256 maxIngestersPerGroup) public {
        groupManagerF.setMaxIngestersPerGroup(maxIngestersPerGroup);
    }

}