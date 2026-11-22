// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IARFitTrace {
    function getProduct(bytes32 productId)
        external
        view
        returns (bool, bytes32, string memory, string memory, string memory, bytes32, uint64, bool);
    function operators(address) external view returns (bool);
    function owner() external view returns (address);
}

/// @title ARFitUnits
/// @notice Registro de unidades físicas (una por prenda fabricada) del
///         marketplace AR-FIT. Complementa a ARFitTrace, que registra el modelo
///         de la prenda: aquí cada unidad tiene un número de serie único, el
///         código de barras (GTIN/EAN-13) de su etiqueta y, cuando el comprador
///         la recibe, su activación a nombre del dueño.
///
///         La serie nunca se guarda en claro: unitId = keccak256(serie). Así,
///         leer el registro on-chain no permite fabricar etiquetas válidas.
///         Almacenamiento compacto (2 slots por unidad) para abaratar el gas.
contract ARFitUnits {
    struct Unit {
        bytes32 productId; // = keccak256(uuid de la prenda), igual que en ARFitTrace
        uint64 gtin;       // código de barras EAN-13 de la etiqueta (13 dígitos)
        uint64 issuedAt;
        uint64 claimedAt;  // 0 mientras nadie la haya activado
        bytes8 size;       // talla en ASCII ("M", "XL"...)
        bytes32 ownerRef;  // keccak256(uuid del comprador) tras la activación
    }

    IARFitTrace public immutable trace;
    mapping(bytes32 => Unit) private units;
    uint256 public unitCount;

    event UnitsIssued(bytes32 indexed productId, uint64 gtin, bytes8 size, uint256 count);
    event UnitClaimed(bytes32 indexed unitId, bytes32 indexed ownerRef);

    /// @dev Reutiliza el control de acceso de ARFitTrace: los operadores de la
    ///      trazabilidad son los mismos que emiten etiquetas.
    modifier onlyOperator() {
        require(trace.operators(msg.sender) || trace.owner() == msg.sender, "not operator");
        _;
    }

    constructor(address traceAddress) {
        trace = IARFitTrace(traceAddress);
    }

    /// @notice Emite un lote de unidades de una prenda ya registrada en ARFitTrace.
    function issueUnits(bytes32 productId, bytes8 size, uint64 gtin, bytes32[] calldata unitIds) external onlyOperator {
        (bool exists, , , , , , , ) = trace.getProduct(productId);
        require(exists, "unknown product");
        require(gtin >= 1e12 && gtin < 1e13, "gtin must be EAN-13");
        uint64 now_ = uint64(block.timestamp);
        for (uint256 i = 0; i < unitIds.length; i++) {
            Unit storage u = units[unitIds[i]];
            require(u.issuedAt == 0, "unit exists");
            u.productId = productId;
            u.gtin = gtin;
            u.issuedAt = now_;
            u.size = size;
        }
        unitCount += unitIds.length;
        emit UnitsIssued(productId, gtin, size, unitIds.length);
    }

    /// @notice Activa la unidad a nombre de su comprador. Solo ocurre una vez:
    ///         una segunda activación delataría una etiqueta clonada.
    function claimUnit(bytes32 unitId, bytes32 ownerRef) external onlyOperator {
        Unit storage u = units[unitId];
        require(u.issuedAt != 0, "unknown unit");
        require(u.claimedAt == 0, "already claimed");
        require(ownerRef != bytes32(0), "empty owner");
        u.ownerRef = ownerRef;
        u.claimedAt = uint64(block.timestamp);
        emit UnitClaimed(unitId, ownerRef);
    }

    /// @dev Getter con valores planos para la lectura directa desde la app (eth_call).
    function getUnit(bytes32 unitId)
        external
        view
        returns (
            bool exists,
            bytes32 productId,
            bytes8 size,
            uint64 gtin,
            uint64 issuedAt,
            bytes32 ownerRef,
            uint64 claimedAt
        )
    {
        Unit storage u = units[unitId];
        return (u.issuedAt != 0, u.productId, u.size, u.gtin, u.issuedAt, u.ownerRef, u.claimedAt);
    }
}
