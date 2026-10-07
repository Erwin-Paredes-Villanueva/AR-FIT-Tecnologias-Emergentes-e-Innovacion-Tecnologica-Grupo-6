// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ARFitTrace
/// @notice Registro de autenticidad, procedencia y trazabilidad de prendas del
///         marketplace phygital AR-FIT. Los identificadores off-chain (UUID de
///         Supabase) se guardan como keccak256 para no exponer datos personales.
contract ARFitTrace {
    enum Status {
        Created,    // 0 pedido creado y pagado (comprador)
        Prepared,   // 1 preparado y empacado (proveedor)
        PickedUp,   // 2 recogido por el transportista
        InTransit,  // 3 en tránsito (transportista)
        Delivered,  // 4 entregado en destino (transportista)
        Received,   // 5 recepción confirmada (comprador)
        Cancelled   // 6 cancelado
    }

    struct Product {
        bytes32 supplierRef;
        string name;
        string origin;
        string materials;
        bytes32 dataHash;      // sha256 de la ficha completa off-chain
        uint64 registeredAt;
        bool verified;         // verificado por un administrador
        bool exists;
    }

    struct Order {
        bytes32 buyerRef;
        bytes32 supplierRef;
        bytes32[] productIds;
        Status status;
        uint64 createdAt;
        bool exists;
    }

    struct TraceEvent {
        Status status;
        string location;
        string actorRole;
        bytes32 actorRef;
        string note;
        uint64 timestamp;
    }

    address public owner;
    mapping(address => bool) public operators;

    mapping(bytes32 => Product) private products;
    mapping(bytes32 => Order) private orders;
    mapping(bytes32 => TraceEvent[]) private orderEvents;
    bytes32[] public productIndex;
    uint256 public orderCount;

    event OperatorSet(address indexed operator, bool enabled);
    event ProductRegistered(bytes32 indexed productId, bytes32 indexed supplierRef, bytes32 dataHash);
    event ProductUpdated(bytes32 indexed productId, bytes32 dataHash);
    event ProductVerified(bytes32 indexed productId, bool verified);
    event OrderCreated(bytes32 indexed orderId, bytes32 indexed buyerRef, bytes32 indexed supplierRef);
    event OrderStatusChanged(bytes32 indexed orderId, Status status, string actorRole, string location);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    modifier onlyOperator() {
        require(operators[msg.sender] || msg.sender == owner, "not operator");
        _;
    }

    constructor() {
        owner = msg.sender;
        operators[msg.sender] = true;
        emit OperatorSet(msg.sender, true);
    }

    function setOperator(address operator, bool enabled) external onlyOwner {
        operators[operator] = enabled;
        emit OperatorSet(operator, enabled);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero address");
        owner = newOwner;
    }

    // ---------------------------------------------------------------- products

    function registerProduct(
        bytes32 productId,
        bytes32 supplierRef,
        string calldata name,
        string calldata origin,
        string calldata materials,
        bytes32 dataHash
    ) external onlyOperator {
        require(!products[productId].exists, "product exists");
        products[productId] = Product({
            supplierRef: supplierRef,
            name: name,
            origin: origin,
            materials: materials,
            dataHash: dataHash,
            registeredAt: uint64(block.timestamp),
            verified: false,
            exists: true
        });
        productIndex.push(productId);
        emit ProductRegistered(productId, supplierRef, dataHash);
    }

    /// @notice Registro por lotes (carga inicial de un catálogo ya auditado).
    function registerProducts(
        bytes32[] calldata productIds,
        bytes32[] calldata supplierRefs,
        string[] calldata names,
        string[] calldata origins,
        string[] calldata materials,
        bytes32[] calldata dataHashes,
        bool verified
    ) external onlyOperator {
        uint256 n = productIds.length;
        require(
            supplierRefs.length == n && names.length == n && origins.length == n &&
            materials.length == n && dataHashes.length == n,
            "length mismatch"
        );
        for (uint256 i = 0; i < n; i++) {
            if (products[productIds[i]].exists) continue;
            products[productIds[i]] = Product({
                supplierRef: supplierRefs[i],
                name: names[i],
                origin: origins[i],
                materials: materials[i],
                dataHash: dataHashes[i],
                registeredAt: uint64(block.timestamp),
                verified: verified,
                exists: true
            });
            productIndex.push(productIds[i]);
            emit ProductRegistered(productIds[i], supplierRefs[i], dataHashes[i]);
            if (verified) emit ProductVerified(productIds[i], true);
        }
    }

    /// @notice Actualiza el hash de la ficha cuando el proveedor edita la prenda.
    ///         Los datos de procedencia (origen/materiales) son inmutables.
    function updateProductHash(bytes32 productId, bytes32 dataHash) external onlyOperator {
        require(products[productId].exists, "unknown product");
        products[productId].dataHash = dataHash;
        emit ProductUpdated(productId, dataHash);
    }

    function setProductVerified(bytes32 productId, bool verified) external onlyOperator {
        require(products[productId].exists, "unknown product");
        products[productId].verified = verified;
        emit ProductVerified(productId, verified);
    }

    /// @dev Getters con valores planos (sin structs) para facilitar la lectura
    ///      directa desde la app móvil vía eth_call.
    function getProduct(bytes32 productId)
        external
        view
        returns (
            bool exists,
            bytes32 supplierRef,
            string memory name,
            string memory origin,
            string memory materials,
            bytes32 dataHash,
            uint64 registeredAt,
            bool verified
        )
    {
        Product storage p = products[productId];
        return (p.exists, p.supplierRef, p.name, p.origin, p.materials, p.dataHash, p.registeredAt, p.verified);
    }

    function productCount() external view returns (uint256) {
        return productIndex.length;
    }

    // ------------------------------------------------------------------ orders

    function createOrder(
        bytes32 orderId,
        bytes32 buyerRef,
        bytes32 supplierRef,
        bytes32[] calldata productIds,
        string calldata location
    ) external onlyOperator {
        require(!orders[orderId].exists, "order exists");
        require(productIds.length > 0, "no products");
        for (uint256 i = 0; i < productIds.length; i++) {
            require(products[productIds[i]].exists, "unknown product");
        }
        Order storage o = orders[orderId];
        o.buyerRef = buyerRef;
        o.supplierRef = supplierRef;
        o.productIds = productIds;
        o.status = Status.Created;
        o.createdAt = uint64(block.timestamp);
        o.exists = true;
        orderCount++;

        orderEvents[orderId].push(TraceEvent({
            status: Status.Created,
            location: location,
            actorRole: "comprador",
            actorRef: buyerRef,
            note: "Pedido creado y pagado",
            timestamp: uint64(block.timestamp)
        }));
        emit OrderCreated(orderId, buyerRef, supplierRef);
        emit OrderStatusChanged(orderId, Status.Created, "comprador", location);
    }

    /// @notice Agrega un evento de trazabilidad. El estado solo puede avanzar
    ///         (o cancelarse antes de ser recogido), lo que impide reescribir
    ///         el historial del envío.
    function addEvent(
        bytes32 orderId,
        Status status,
        string calldata location,
        string calldata actorRole,
        bytes32 actorRef,
        string calldata note
    ) external onlyOperator {
        Order storage o = orders[orderId];
        require(o.exists, "unknown order");
        require(o.status != Status.Cancelled && o.status != Status.Received, "order closed");
        if (status == Status.Cancelled) {
            require(uint8(o.status) < uint8(Status.PickedUp), "already shipped");
        } else if (status == Status.InTransit) {
            // se permiten varios puntos de control en tránsito
            require(o.status == Status.PickedUp || o.status == Status.InTransit, "invalid transition");
        } else {
            require(uint8(status) == uint8(o.status) + 1, "invalid transition");
        }
        o.status = status;
        orderEvents[orderId].push(TraceEvent({
            status: status,
            location: location,
            actorRole: actorRole,
            actorRef: actorRef,
            note: note,
            timestamp: uint64(block.timestamp)
        }));
        emit OrderStatusChanged(orderId, status, actorRole, location);
    }

    function getOrder(bytes32 orderId)
        external
        view
        returns (bool exists, bytes32 buyerRef, bytes32 supplierRef, uint8 status, uint64 createdAt, uint256 orderProducts, uint256 eventCount)
    {
        Order storage o = orders[orderId];
        return (o.exists, o.buyerRef, o.supplierRef, uint8(o.status), o.createdAt, o.productIds.length, orderEvents[orderId].length);
    }

    function getOrderProduct(bytes32 orderId, uint256 index) external view returns (bytes32) {
        return orders[orderId].productIds[index];
    }

    function getOrderEvent(bytes32 orderId, uint256 index)
        external
        view
        returns (uint8 status, string memory location, string memory actorRole, bytes32 actorRef, string memory note, uint64 timestamp)
    {
        TraceEvent storage e = orderEvents[orderId][index];
        return (uint8(e.status), e.location, e.actorRole, e.actorRef, e.note, e.timestamp);
    }
}
