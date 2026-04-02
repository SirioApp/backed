// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Sale} from "../launch/Sale.sol";
import {AgentExecutor} from "./AgentExecutor.sol";
import {ISale} from "../interfaces/ISale.sol";
import {IERC8004IdentityRegistry} from "../interfaces/IERC8004IdentityRegistry.sol";
import {ISafe, ISafeProxyFactory, ISafeSetup, ISafeModuleSetup} from "../interfaces/ISafe.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    DEFAULT_MAX_RAISE,
    DEFAULT_MIN_RAISE,
    DEFAULT_PLATFORM_FEE_BPS,
    BPS
} from "../Constants.sol";

/// @title AgentRaiseFactory
/// @notice Entry point for creating agent projects on the platform.
///
/// For each project the factory:
///   1. Creates a Gnosis Safe (treasury) owned by the agent owner.
///   2. Deploys a Sale contract for the TGE.
///   3. Deploys an AgentExecutor Safe module, enables it on the Safe,
///      then removes itself as a Safe module — leaving AgentExecutor as
///      the sole module with execution rights.
///
/// Ongoing admin controls:
///   - Projects must be explicitly approved before investors can commit.
///   - Admin can revoke approval or trigger an emergency refund.
contract AgentRaiseFactory {
    IERC8004IdentityRegistry public immutable IDENTITY_REGISTRY;
    address public immutable SAFE_PROXY_FACTORY;
    address public immutable SAFE_SINGLETON;
    address public immutable SAFE_FALLBACK_HANDLER;
    address public immutable SAFE_MODULE_SETUP;
    address public immutable ADMIN;
    address public immutable ALLOWLIST;

    struct GlobalConfig {
        uint256 minRaise;
        uint256 maxRaise;
        uint16 platformFeeBps;
        address platformFeeRecipient;
        uint256 minDuration;
        uint256 maxDuration;
        uint256 minLaunchDelay;
        uint256 maxLaunchDelay;
    }

    struct AgentProject {
        uint256 agentId;
        string name;
        string description;
        string categories;
        address agent;
        address treasury;
        address sale;
        address agentExecutor;
        address collateral;
        uint8 operationalStatus;
        string statusNote;
        uint256 createdAt;
        uint256 updatedAt;
    }

    struct ProjectRaiseSnapshot {
        bool approved;
        uint256 totalCommitted;
        uint256 acceptedAmount;
        bool finalized;
        bool failed;
        bool active;
        uint256 startTime;
        uint256 endTime;
        address shareToken;
    }

    uint8 public constant STATUS_RAISING = 0;
    uint8 public constant STATUS_DEPLOYING = 1;
    uint8 public constant STATUS_OPERATING = 2;
    uint8 public constant STATUS_PAUSED = 3;
    uint8 public constant STATUS_CLOSED = 4;
    uint8 public constant MAX_OPERATIONAL_STATUS = STATUS_CLOSED;

    AgentProject[] internal _projects;
    mapping(uint256 => uint256[]) internal _agentProjects;
    mapping(uint256 => bool) public projectApproved;
    mapping(address => bool) public allowedCollateral;
    GlobalConfig public globalConfig;

    event AgentRaiseCreated(
        uint256 indexed projectId,
        uint256 indexed agentId,
        string name,
        address indexed agent,
        address treasury,
        address sale,
        address agentExecutor,
        address collateral
    );
    event ProjectApproved(uint256 indexed projectId);
    event ProjectRevoked(uint256 indexed projectId);
    event GlobalConfigUpdated(GlobalConfig config);
    event CollateralConfigured(address indexed collateral, bool allowed);
    event ProjectMetadataUpdated(
        uint256 indexed projectId, string description, string categories, address indexed updatedBy
    );
    event ProjectOperationalStatusUpdated(
        uint256 indexed projectId, uint8 status, string statusNote, address indexed updatedBy
    );

    error InvalidAddress();
    error NotAgentOwner();
    error InvalidParams();
    error InvalidConfig();
    error InvalidDuration();
    error InvalidLaunchTime();
    error ProjectNotFound();
    error SafeCreationFailed();
    error ModuleSetupFailed();
    error ProjectAlreadyApproved();
    error ProjectNotApprovedError();
    error Unauthorized();
    error UnsupportedTokenDecimals();
    error UnsupportedCollateral();
    error InvalidOperationalStatus();

    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    modifier onlyProjectOperator(uint256 projectId) {
        _onlyProjectOperator(projectId);
        _;
    }

    function _onlyAdmin() internal view {
        if (msg.sender != ADMIN) revert Unauthorized();
    }

    function _onlyProjectOperator(uint256 projectId) internal view {
        if (projectId >= _projects.length) revert ProjectNotFound();
        if (msg.sender != ADMIN && msg.sender != _projects[projectId].agent) revert Unauthorized();
    }

    constructor(
        address identityRegistry_,
        address safeProxyFactory_,
        address safeSingleton_,
        address safeFallbackHandler_,
        address safeModuleSetup_,
        address admin_,
        address allowlist_,
        address initialCollateral_
    ) {
        if (identityRegistry_ == address(0)) revert InvalidAddress();
        if (safeProxyFactory_ == address(0)) revert InvalidAddress();
        if (safeSingleton_ == address(0)) revert InvalidAddress();
        if (safeFallbackHandler_ == address(0)) revert InvalidAddress();
        if (safeModuleSetup_ == address(0)) revert InvalidAddress();
        if (admin_ == address(0)) revert InvalidAddress();
        if (allowlist_ == address(0)) revert InvalidAddress();

        IDENTITY_REGISTRY = IERC8004IdentityRegistry(identityRegistry_);
        SAFE_PROXY_FACTORY = safeProxyFactory_;
        SAFE_SINGLETON = safeSingleton_;
        SAFE_FALLBACK_HANDLER = safeFallbackHandler_;
        SAFE_MODULE_SETUP = safeModuleSetup_;
        ADMIN = admin_;
        ALLOWLIST = allowlist_;
        _setCollateral(initialCollateral_, true);

        GlobalConfig memory defaults = GlobalConfig({
            minRaise: DEFAULT_MIN_RAISE,
            maxRaise: DEFAULT_MAX_RAISE,
            platformFeeBps: DEFAULT_PLATFORM_FEE_BPS,
            platformFeeRecipient: admin_,
            minDuration: 0,
            maxDuration: 0,
            minLaunchDelay: 0,
            maxLaunchDelay: 0
        });
        _validateConfig(defaults);
        globalConfig = defaults;
    }

    // ─── Public ──────────────────────────────────────────────────────────

    /// @notice Create a new agent raise project.
    /// @param agentId      ERC-8004 identity NFT token ID. Caller must own it.
    /// @param name         Human-readable project name.
    /// @param description  Project/raise description shown on frontend detail pages.
    /// @param categories   Comma-separated categories/tags for discovery/filtering.
    /// @param agentAddress Wallet address of the agent (used as AgentExecutor operator).
    /// @param collateral   Allowed ERC-20 collateral used for commitments.
    /// @param duration     Sale window length in seconds.
    /// @param launchTime   Unix timestamp when the sale window opens.
    /// @param tokenName    ERC-20 name for the vault share token.
    /// @param tokenSymbol  ERC-20 symbol for the vault share token.
    /// @return projectId   Index of the newly created project.
    function createAgentRaise(
        uint256 agentId,
        string calldata name,
        string calldata description,
        string calldata categories,
        address agentAddress,
        address collateral,
        uint256 duration,
        uint256 launchTime,
        string calldata tokenName,
        string calldata tokenSymbol
    ) external returns (uint256 projectId) {
        return _createAgentRaise(
            agentId,
            name,
            description,
            categories,
            agentAddress,
            collateral,
            duration,
            launchTime,
            0,
            tokenName,
            tokenSymbol
        );
    }

    /// @notice Create a new agent raise project with a post-raise investor lockup.
    /// @param lockupMinutes Lockup after the raise ends before shares may be redeemed.
    function createAgentRaise(
        uint256 agentId,
        string calldata name,
        string calldata description,
        string calldata categories,
        address agentAddress,
        address collateral,
        uint256 duration,
        uint256 launchTime,
        uint256 lockupMinutes,
        string calldata tokenName,
        string calldata tokenSymbol
    ) external returns (uint256 projectId) {
        return _createAgentRaise(
            agentId,
            name,
            description,
            categories,
            agentAddress,
            collateral,
            duration,
            launchTime,
            lockupMinutes,
            tokenName,
            tokenSymbol
        );
    }

    function _createAgentRaise(
        uint256 agentId,
        string calldata name,
        string calldata description,
        string calldata categories,
        address agentAddress,
        address collateral,
        uint256 duration,
        uint256 launchTime,
        uint256 lockupMinutes,
        string calldata tokenName,
        string calldata tokenSymbol
    ) internal returns (uint256 projectId) {
        if (IDENTITY_REGISTRY.ownerOf(agentId) != msg.sender) {
            revert NotAgentOwner();
        }
        if (bytes(name).length == 0 || duration == 0 || launchTime == 0) revert InvalidParams();
        if (agentAddress == address(0)) revert InvalidAddress();
        if (!allowedCollateral[collateral]) revert UnsupportedCollateral();

        GlobalConfig memory cfg = globalConfig;
        if (launchTime < block.timestamp) revert InvalidLaunchTime();
        uint8 collateralDecimals = _collateralDecimals(collateral);
        uint256 scaledMinRaise = _scaleFrom18Decimals(cfg.minRaise, collateralDecimals);
        uint256 scaledMaxRaise = _scaleFrom18Decimals(cfg.maxRaise, collateralDecimals);
        if (scaledMinRaise == 0 || scaledMaxRaise == 0 || scaledMinRaise > scaledMaxRaise) {
            revert InvalidConfig();
        }

        projectId = _projects.length;

        address treasury = _createSafe(msg.sender, projectId);

        Sale sale = new Sale(
            collateral,
            treasury,
            msg.sender,
            duration,
            launchTime,
            lockupMinutes,
            tokenName,
            tokenSymbol,
            address(this),
            ISale.SaleConfigSnapshot({
                minRaise: scaledMinRaise,
                maxRaise: scaledMaxRaise,
                platformFeeBps: cfg.platformFeeBps,
                platformFeeRecipient: cfg.platformFeeRecipient
            }),
            projectId
        );

        AgentExecutor executor = new AgentExecutor(agentAddress, treasury, ALLOWLIST, ADMIN);

        _setupSafeModules(ISafe(treasury), address(executor));

        _projects.push(
            AgentProject({
                agentId: agentId,
                name: name,
                description: description,
                categories: categories,
                agent: msg.sender,
                treasury: treasury,
                sale: address(sale),
                agentExecutor: address(executor),
                collateral: collateral,
                operationalStatus: STATUS_RAISING,
                statusNote: "Raise created",
                createdAt: block.timestamp,
                updatedAt: block.timestamp
            })
        );

        _agentProjects[agentId].push(projectId);

        emit AgentRaiseCreated(
            projectId,
            agentId,
            name,
            msg.sender,
            treasury,
            address(sale),
            address(executor),
            collateral
        );
    }

    /// @notice Approve a project so investors can commit to its sale.
    function approveProject(uint256 projectId) external onlyAdmin {
        if (projectId >= _projects.length) revert ProjectNotFound();
        if (projectApproved[projectId]) revert ProjectAlreadyApproved();
        projectApproved[projectId] = true;
        emit ProjectApproved(projectId);
    }

    /// @notice Revoke a previously granted project approval.
    function revokeProject(uint256 projectId) external onlyAdmin {
        if (projectId >= _projects.length) revert ProjectNotFound();
        if (!projectApproved[projectId]) revert ProjectNotApprovedError();
        projectApproved[projectId] = false;
        emit ProjectRevoked(projectId);
    }

    function setGlobalConfig(GlobalConfig calldata config_) external onlyAdmin {
        _validateConfig(config_);
        globalConfig = config_;
        emit GlobalConfigUpdated(config_);
    }

    function setAllowedCollateral(address collateral, bool allowed) external onlyAdmin {
        _setCollateral(collateral, allowed);
    }

    function updateProjectMetadata(
        uint256 projectId,
        string calldata description,
        string calldata categories
    ) external onlyAdmin {
        if (projectId >= _projects.length) revert ProjectNotFound();
        AgentProject storage project = _projects[projectId];
        project.description = description;
        project.categories = categories;
        project.updatedAt = block.timestamp;
        emit ProjectMetadataUpdated(projectId, description, categories, msg.sender);
    }

    function updateProjectOperationalStatus(
        uint256 projectId,
        uint8 status,
        string calldata statusNote
    ) external onlyProjectOperator(projectId) {
        if (status > MAX_OPERATIONAL_STATUS) revert InvalidOperationalStatus();
        AgentProject storage project = _projects[projectId];
        project.operationalStatus = status;
        project.statusNote = statusNote;
        project.updatedAt = block.timestamp;
        emit ProjectOperationalStatusUpdated(projectId, status, statusNote, msg.sender);
    }

    function getProjectRaiseSnapshot(uint256 projectId)
        external
        view
        returns (ProjectRaiseSnapshot memory snapshot)
    {
        if (projectId >= _projects.length) revert ProjectNotFound();
        address saleAddress = _projects[projectId].sale;
        ISale sale = ISale(saleAddress);
        snapshot = ProjectRaiseSnapshot({
            approved: projectApproved[projectId],
            totalCommitted: sale.totalCommitted(),
            acceptedAmount: sale.acceptedAmount(),
            finalized: sale.finalized(),
            failed: sale.failed(),
            active: sale.isActive(),
            startTime: sale.startTime(),
            endTime: sale.endTime(),
            shareToken: sale.token()
        });
    }

    function getProjectCommitment(uint256 projectId, address user) external view returns (uint256) {
        if (projectId >= _projects.length) revert ProjectNotFound();
        return ISale(_projects[projectId].sale).commitments(user);
    }

    // ─── ISaleFactory view ───────────────────────────────────────────────

    function SUPER_ADMIN() external view returns (address) {
        return ADMIN;
    }

    function isProjectApproved(uint256 id) external view returns (bool) {
        return projectApproved[id];
    }

    /// @notice Returns the global maximum raise amount in 18-decimal normalized units.
    function maxRaise() external view returns (uint256) {
        return globalConfig.maxRaise;
    }

    function maxRaiseForCollateral(address collateral) external view returns (uint256) {
        return _scaleFrom18Decimals(globalConfig.maxRaise, _collateralDecimals(collateral));
    }

    function minRaiseForCollateral(address collateral) external view returns (uint256) {
        return _scaleFrom18Decimals(globalConfig.minRaise, _collateralDecimals(collateral));
    }

    // ─── Project views ───────────────────────────────────────────────────

    function projectCount() external view returns (uint256) {
        return _projects.length;
    }

    function getAgentProjects(uint256 agentId) external view returns (uint256[] memory) {
        return _agentProjects[agentId];
    }

    function getProject(uint256 id) external view returns (AgentProject memory) {
        if (id >= _projects.length) revert ProjectNotFound();
        return _projects[id];
    }

    // ─── Internal ────────────────────────────────────────────────────────

    /// @dev Deploy a 1-of-1 Safe with the factory as the sole initial module (setup only).
    function _createSafe(address owner, uint256 projectId) internal returns (address) {
        address[] memory owners = new address[](1);
        owners[0] = owner;

        address[] memory modules = new address[](1);
        modules[0] = address(this);
        bytes memory moduleSetupData =
            abi.encodeWithSelector(ISafeModuleSetup.enableModules.selector, modules);

        bytes memory initData = abi.encodeWithSelector(
            ISafeSetup.setup.selector,
            owners,
            1,
            SAFE_MODULE_SETUP,
            moduleSetupData,
            SAFE_FALLBACK_HANDLER,
            address(0),
            0,
            payable(address(0))
        );

        uint256 salt =
            uint256(keccak256(abi.encodePacked(address(this), owner, projectId, block.timestamp)));
        address safe = ISafeProxyFactory(SAFE_PROXY_FACTORY)
            .createProxyWithNonce(SAFE_SINGLETON, initData, salt);
        if (safe == address(0)) revert SafeCreationFailed();
        return safe;
    }

    /// @dev Enable AgentExecutor as a Safe module, then remove factory from the module list.
    ///
    /// Module linked-list state after _createSafe:
    ///   SENTINEL → factory → SENTINEL
    ///
    /// After enableModule(executor):
    ///   SENTINEL → executor → factory → SENTINEL
    ///
    /// After disableModule(prevModule=executor, module=factory):
    ///   SENTINEL → executor → SENTINEL
    ///
    /// The factory retains no ongoing privileged access to the Safe.
    function _setupSafeModules(ISafe safe, address executor) internal {
        bool ok;

        // Enable AgentExecutor
        bytes memory enableData = abi.encodeWithSelector(ISafe.enableModule.selector, executor);
        ok = safe.execTransactionFromModule(address(safe), 0, enableData, ISafe.Operation.Call);
        if (!ok) revert ModuleSetupFailed();

        // Remove factory (self) — prevModule is executor because Safe prepends on enable
        bytes memory disableData =
            abi.encodeWithSelector(ISafe.disableModule.selector, executor, address(this));
        ok = safe.execTransactionFromModule(address(safe), 0, disableData, ISafe.Operation.Call);
        if (!ok) revert ModuleSetupFailed();
    }

    function _validateConfig(GlobalConfig memory config_) internal pure {
        if (config_.minRaise == 0) revert InvalidConfig();
        if (config_.maxRaise == 0 || config_.minRaise > config_.maxRaise) revert InvalidConfig();
        if (config_.platformFeeBps >= BPS) revert InvalidConfig();
        if (config_.platformFeeRecipient == address(0)) revert InvalidAddress();
    }

    function _scaleFrom18Decimals(uint256 amount, uint8 toDecimals)
        internal
        pure
        returns (uint256)
    {
        if (toDecimals == 18) return amount;
        if (toDecimals < 18) return amount / (10 ** (18 - toDecimals));
        return amount * (10 ** (toDecimals - 18));
    }

    function _collateralDecimals(address collateral) internal view returns (uint8 decimals) {
        if (collateral == address(0)) revert InvalidAddress();
        (bool ok, bytes memory data) =
            collateral.staticcall(abi.encodeWithSelector(IERC20Metadata.decimals.selector));
        if (!ok || data.length < 32) revert UnsupportedCollateral();
        decimals = abi.decode(data, (uint8));
        if (decimals > 36) revert UnsupportedTokenDecimals();
    }

    function _setCollateral(address collateral, bool allowed) internal {
        if (collateral == address(0)) revert InvalidAddress();
        if (allowed) _collateralDecimals(collateral);
        allowedCollateral[collateral] = allowed;
        emit CollateralConfigured(collateral, allowed);
    }
}
