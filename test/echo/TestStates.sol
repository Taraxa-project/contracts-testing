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
    uint256 maxUsers = 25;
    uint256 maxGroups = 200;
    string message = "test";
    uint256 nonce = 999;
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

contract TestUtilities is StateDeployDiamondBase{

    function addGroupsWFuzz(uint256 amountOfGroups) public {
        vm.assume(amountOfGroups > 0);
        vm.assume(amountOfGroups < maxGroups);


        for (uint i = 0; i < amountOfGroups; i++) {
            string memory groupName = string(abi.encodePacked("group", Strings.toString(i)));
            try groupManagerF.getGroup(groupName) {
            // The group exists, so do nothing and continue to the next iteration
                continue;
            } catch {
                // The group doesn't exist (the getGroup call reverted), so add it
                groupManagerF.addGroup(groupName);
            }
        }
    }

    function addGroups(uint256 amountOfGroups) public {
        for (uint i = 0; i < amountOfGroups; i++) {
            string memory groupName = string(abi.encodePacked("group", Strings.toString(i)));
            try groupManagerF.getGroup(groupName) {
            // The group exists, so do nothing and continue to the next iteration
                continue;
            } catch {
                // The group doesn't exist (the getGroup call reverted), so add it
                groupManagerF.addGroup(groupName);
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

    function removeGroupsWFuzz(uint256 amountOfGroups) public {
        vm.assume(amountOfGroups > 0);
        vm.assume(amountOfGroups < maxGroups);

        for (uint i = 0; i < amountOfGroups; i++) {
            string memory groupName = string(abi.encodePacked("group", Strings.toString(i)));
            
            try groupManagerF.getGroup(groupName) {
            // The group exists, so do nothing and continue to the next iteration
                IIngesterGroupManager.GroupWithIngesters memory groupToRemove = groupManagerF.getGroup(groupName);
                address[] memory groupIngesters = groupToRemove.ingesterAddresses;
                groupManagerF.removeGroup(groupName);
            
                for (uint256 i = 0; i < groupIngesters.length; i++) {
                    IIngesterRegistration.IngesterWithGroups memory ingester = registryF.getIngesterWithGroups(groupIngesters[i]);
                    assert(!utils.containsStr(ingester.assignedGroups, groupName));
                }
            } catch {
                // The group doesn't exist (the getGroup call reverted), so add it
                continue;
            }
        }
    }

    function removeGroups(uint256 amountOfGroups) public {
        for (uint i = 0; i < amountOfGroups; i++) {
            string memory groupName = string(abi.encodePacked("group", Strings.toString(i)));
            
            try groupManagerF.getGroup(groupName) {
            // The group exists, so do nothing and continue to the next iteration
                IIngesterGroupManager.GroupWithIngesters memory groupToRemove = groupManagerF.getGroup(groupName);
                address[] memory groupIngesters = groupToRemove.ingesterAddresses;
                groupManagerF.removeGroup(groupName);
            
                for (uint256 i = 0; i < groupIngesters.length; i++) {
                    IIngesterRegistration.IngesterWithGroups memory ingester = registryF.getIngesterWithGroups(groupIngesters[i]);
                    assert(!utils.containsStr(ingester.assignedGroups, groupName));
                }
            } catch {
                // The group doesn't exist (the getGroup call reverted), so add it
                continue;
            }
        }
    }

    function registerIngestersWFuzz(uint256 numIngesters) public {
        vm.assume(numIngesters < maxUsers);
        
        for (uint256 i = 1; i < numIngesters; i++) {
            try registryF.getIngester(users[i]) {
                continue;
            } catch {
                bytes memory signature = hashAndSignMessage(users[i], users_priv_key[i-1], message, nonce);
                vm.startPrank(users[i-1]);
                registryF.registerIngester(users[i], message, nonce, signature);
                vm.stopPrank();
            }
        }
    }

    function registerIngesters(uint256 numIngesters) public {
        require(numIngesters <= maxUsers, "Too many users");
        
        for (uint256 i = 1; i < numIngesters; i++) {
            try registryF.getIngester(users[i]) {
                // The ingester exists, so do nothing and continue to the next iteration
                continue;
            } catch {
                // The ingester doesn't exist (the getIngester call reverted), so register it
                bytes memory signature = hashAndSignMessage(users[i], users_priv_key[i-1], message, nonce);
                vm.startPrank(users[i-1]);
                registryF.registerIngester(users[i], message, nonce, signature);
                vm.stopPrank();
            }
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

    function registerIngestersWithSameController(uint256 numIngesters) public {

        for (uint256 i = 1; i <= numIngesters; i++) {
            bytes memory signature = hashAndSignMessage(users[i], users_priv_key[0], message, nonce);
            vm.startPrank(users[0]);
            registryF.registerIngester(users[i], message, nonce, signature);
            vm.stopPrank();
        }
    }

    function unRegisterIngester(address user, address controller) public {
        vm.startPrank(controller);
        registryF.unRegisterIngester(user);
        vm.stopPrank();
    }

    function unRegisterIngestersWFuzz(uint256 numIngesters) public {
        address[] memory ingesters = registryF.getIngesters();
        vm.assume(numIngesters > 0);
        vm.assume(numIngesters < ingesters.length);

        for (uint256 i = 1; i < numIngesters; i++) {
            try registryF.getIngester(users[i]) {
                unRegisterIngester(users[i], users[i-1]);
            } catch {
                vm.expectRevert();
                unRegisterIngester(users[i], users[i-1]);
            }
        }
    }

    function unRegisterIngesters(uint256 numIngesters) public {
        for (uint256 i = 1; i <= numIngesters; i++) {
            //TODO: verify why roles are still present when their addresses are no longer registered
            // console.log('checking ingester users[i]', users[i]);
            // console.log('checking controller users[i-1]', users[i-1]);
            
            // address[] memory ingesters = registryF.getIngesters();
            // bool contains = utils.containsAddr(ingesters, users[i]);
            // console.log('contains ingester in ingesters array', contains);

            // IIngesterRegistration.Ingester[] memory ingesterAddresses = registryF.getControllerIngesters(users[i-1]);
            // console.log('ingesterAddresses.length', ingesterAddresses.length);
            // for (uint j = 0; j < ingesterAddresses.length; j++) {
            //     console.log('ingesterAddresses[j]', ingesterAddresses[j].ingesterAddress);
            // }
            // address controllerAddress = registryF.getIngesterController(users[i]);
            // console.log('controllerAddress in contract', controllerAddress);
            // bool isRegisteredIngester = registryF.isRegisteredIngester(users[i]);
            // bool isRegistedController = registryF.isRegisteredController(users[i-1]);
            // console.log('isRegisteredIngester', isRegisteredIngester);
            // console.log('isRegistedController', isRegistedController);

            // IIngesterRegistration.Ingester memory ingester = registryF.getIngester(users[i]);
            // console.log('ingester.ingesterAddress', ingester.ingesterAddress);

            // if (registryF.isRegisteredIngester(users[i]) && registryF.isRegisteredController(users[i-1])) {
            //     unRegisterIngester(users[i], users[i-1]);
            // } else {
            //     vm.expectRevert("Ingester does not exist");
            //     unRegisterIngester(users[i], users[i-1]);
            // }

            try registryF.getIngester(users[i]) {
                unRegisterIngester(users[i], users[i-1]);
            } catch {
                vm.expectRevert();
                unRegisterIngester(users[i], users[i-1]);    
            }
        }
    }
}

contract TestingInvariants is StateDeployDiamondBase {
    uint256 public mappingNonce = 1;
    mapping (uint256 => mapping (address => bool)) public controllers;
    bool verbose = false;

    function assertIngesterPerGroupInvariant() public {
        uint256 maxIngesterPerGroup = groupManagerF.getMaxIngestersPerGroup();
        uint256[] memory clusters = groupManagerF.getClusters();

        for (uint256 i = 0; i < clusters.length; i++) {
            IIngesterGroupManager.GroupsCluster memory cluster = groupManagerF.getCluster(clusters[i]);
            if (verbose){
                console.log('asserting ingester per group invariant');
            }
            assertLe(cluster.ingesterAddresses.length, maxIngesterPerGroup);
        }
    }

    function assertMaxClusterSizeInvariant() public {
        uint256 maxClusterSize = groupManagerF.getMaxClusterSize();
        uint256[] memory clusters = groupManagerF.getClusters();

        for (uint256 i = 0; i < clusters.length; i++) {
            IIngesterGroupManager.GroupsCluster memory cluster = groupManagerF.getCluster(clusters[i]);
            if (verbose){
                console.log('asserting max cluster size invariant');
            }
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
        if (verbose){
            console.log('asserting group count invariant');
        }
        assertEq(groupCountCheck, groupCount);
    }

    function assertIngesterRoleCount() public {
        uint256 ingesterCount = groupManagerF.getIngesterCount();
        uint256 ingesterCountCheck = 0;
        uint256 controllerCountCheck = 0;

        for (uint256 i = 1; i < users.length; i++) {
            bool isRegisteredIngester = registryF.isRegisteredIngester(users[i]);
            bool isRegisteredController = registryF.isRegisteredController(vm.addr(uint256(users_priv_key[i-1])));

            if (isRegisteredIngester) {
                ingesterCountCheck += 1;
            }
            if (isRegisteredController) {
                controllerCountCheck += 1;
            }
        }

        assertEq(ingesterCountCheck, ingesterCount);
        assertLe(controllerCountCheck, ingesterCount);
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
        if (verbose){
            console.log('asserting inactive clusters');
            console.log('inactiveClusterCheck', inactiveClusterCheck);
            console.log('inactiveClusters.length', inactiveClusters.length);
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
                if (verbose){
                    console.log('asserting unique controllers');
                    console.log('controllers[mappingNonce][controllerAddress]', controllers[mappingNonce][controllerAddress]);
                }
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
        assertIngesterRoleCount();
    }
}

contract StateAllFacetsNoReplication is StateDeployDiamondBase, TestUtilities {


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

contract StateAddAllFacetsWithReplicationPopulated is StateAddAllFacetsWithReplication{
 
    function setUp() public virtual override {
        StateAddAllFacetsWithReplication.setUp();
    
        addGroups(maxGroups);
        registerIngesters(maxUsers - 1);
    }
}