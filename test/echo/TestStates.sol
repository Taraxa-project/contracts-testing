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
import "@openzeppelin/contracts/utils/Strings.sol";


abstract contract StateDeployDiamondBase is HelperContract {
    Utils internal utils;
    uint256 maxUsers = 100;
    address[] users;
    bytes32[] users_priv_key;
    address owner;


    //contract types of facets to be deployed
    Diamond diamond;
    DiamondCutFacet dCutFacet;
    DiamondLoupeFacet dLoupe;
    OwnershipFacet ownerF;
    AccessControlFacet accessF;
    CommonFunctionsFacet commonFunctionsF;
    DataGatheringFacet dataF;
    GroupManagerFacet groupManagerF;
    RegistryFacet registryF;
    IDiamondLoupe ILoupe;
    IDiamondCut ICut;

    string[] facetNames;
    address[] facetAddressList;

    // deploys diamond and connects facets
    function setUp() public virtual {
        //Define Users
        owner = address(this);
        utils = new Utils();
        (users, users_priv_key) = utils.createUsers(maxUsers);

        //deploy facets
        dCutFacet = new DiamondCutFacet();
        dLoupe = new DiamondLoupeFacet();
        ownerF = new OwnershipFacet();
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

        // Diamond arguments
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

        //build cut struct
        FacetCut[] memory cut = new FacetCut[](7);

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
        cut[2] =
        FacetCut({
            facetAddress: address(accessF),
            action: FacetCutAction.Add,
            functionSelectors: selectorsAccess
        });

        cut[3] =
        FacetCut({
            facetAddress: address(commonFunctionsF),
            action: FacetCutAction.Add,
            functionSelectors: selectorsCommon
        });

        cut[4] =
        FacetCut({
            facetAddress: address(dataF),
            action: FacetCutAction.Add,
            functionSelectors: selectorsDataWShared
        });

        cut[5] =
        FacetCut({
            facetAddress: address(groupManagerF),
            action: FacetCutAction.Add,
            functionSelectors: selectorsGroupsWShared
        });

        cut[6] =
        FacetCut({
            facetAddress: address(registryF),
            action: FacetCutAction.Add,
            functionSelectors: selectorsRegistryWShared
        });


        // initialise interfaces
        ILoupe = IDiamondLoupe(address(diamond));
        ICut = IDiamondCut(address(diamond));

        //upgrade diamond
        ICut.diamondCut(cut, address(0x0), "");

        accessF = AccessControlFacet(address(diamond));
        commonFunctionsF = CommonFunctionsFacet(address(diamond));
        dataF = DataGatheringFacet(address(diamond));
        groupManagerF = GroupManagerFacet(address(diamond));
        registryF = RegistryFacet(address(diamond));
        
    }
}

contract TestingInvariants is StateDeployDiamondBase {
    uint256 public mappingNonce = 1;
    mapping (uint256 => mapping (address => bool)) public controllers;

    function assertIngesterPerGroupInvariant() public {
        uint256 maxIngesterPerGroup = groupManagerF.getMaxIngestersPerGroup();
        uint256[] memory clusters = groupManagerF.getClusters();

        for (uint256 i = 0; i < clusters.length; i++) {
            IIngesterGroupManager.GroupsCluster memory cluster = groupManagerF.getCluster(clusters[i]);
            console.log('asserting ingester per group invariant');
            assertLe(cluster.ingesterAddresses.length, maxIngesterPerGroup);
        }
    }

    function assertMaxClusterSizeInvariant() public {
        uint256 maxClusterSize = groupManagerF.getMaxClusterSize();
        uint256[] memory clusters = groupManagerF.getClusters();

        for (uint256 i = 0; i < clusters.length; i++) {
            IIngesterGroupManager.GroupsCluster memory cluster = groupManagerF.getCluster(clusters[i]);
            console.log('asserting max cluster size invariant');
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
        console.log('asserting group count invariant');
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
        ingesterCountCheck += groupManagerF.getunallocatedIngesters().length;

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
        console.log('asserting inactive clusters');
        console.log('inactiveClusterCheck', inactiveClusterCheck);
        console.log('inactiveClusters.length', inactiveClusters.length);
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
                console.log('asserting unique controllers');
                console.log('controllers[mappingNonce][controllerAddress]', controllers[mappingNonce][controllerAddress]);
                assertFalse(controllers[mappingNonce][controllerAddress]);
                controllers[mappingNonce][controllerAddress] = true;
            }
            ++mappingNonce;
        }
    }

    function assertAllInvariants() public {
        assertIngesterPerGroupInvariant();
        assertMaxClusterSizeInvariant();
        assertGroupCountInvariant();
        assertIngesterCountInvariant();
        assertInactiveClusterCountInvariant();
        assertUniqueControllerInClusterInvariant();
    }
}

contract StateAllFacetsNoReplication is StateDeployDiamondBase {


    function setUp() public virtual override {
        super.setUp();
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


contract StateAddAllFacetsWithReplication is StateAllFacetsNoReplication{
    uint256 newMaxIngesterPerGroup = 3;

    function setUp() public virtual override {
        super.setUp();

        setNewMaxIngestersPerGroup(newMaxIngesterPerGroup);
    }
}