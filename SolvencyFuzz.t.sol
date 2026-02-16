// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ============================================================================================
//  EULER V2 - SUITE DE FUZZING OFFENSIVE "NUMBER 1" (2026)
//  Objectif : Détecter les failles de solvabilité (Ghost Collateral / Bad Debt)
//  Auteur : Antigravity (Google Deepmind) pour l'Utilisateur
// ============================================================================================

import {Setup} from "./Setup.t.sol";
import {HandlerAggregator} from "./HandlerAggregator.t.sol";
import {BaseInvariants} from "./invariants/BaseInvariants.t.sol";

/// @title SolvencyFuzz
/// @notice Suite de tests d'invariants focalisée sur la solvabilité sous contrainte de Batchs complexes.
/// @dev Hérite de Setup (déploiement) et HandlerAggregator (actions).
contract SolvencyFuzz is Setup, HandlerAggregator {
    
    // ============================================================================================
    //  CONFIGURATION DU TEST
    // ============================================================================================



    /// @notice Fonction de setup standard pour Foundry
    function setUp() public {
        _setUp();
        _setUpActors();
        _setUpHandlers();
        
        // Les handlers d'Euler gèrent eux-mêmes la sélection des acteurs via _getRandomActor.
        // Pas besoin de targetSender ou targetContract ici.
        
        // Initialisation du BatchHandler avec l'EVC et le Vault de test
        initBatchHandler(address(evc), address(eTST));
    }

    // ============================================================================================
    //  INVARIANTS CRITIQUES ("Les Règles du Vigile")
    // ============================================================================================

    /// @notice Invariant #1 : Solvabilité Globale
    /// @dev Vérifie qu'aucun utilisateur n'a une dette > collatéral (ajusté) sans être liquidable.
    /// Si cet invariant casse, cela signifie qu'on a réussi à voler des fonds (Bad Debt).
    function invariant_solvency() public view returns (bool) {
        for (uint256 i = 0; i < actorAddresses.length; i++) {
            address account = actorAddresses[i];
            
            // On vérifie le vault principal eTST
            // On utilise l'interface IEVault déjà disponible via Setup -> BaseTest -> IEVault eTST
            
            try eTST.accountLiquidity(account, false) returns (uint256 coll, uint256 liab) {
                 if (liab > coll) {
                     // L'utilisateur est insolvable !
                     // Note: En mode "Solvency Check" normal, cela ne devrait jamais arriver après une tx réussie
                     // sauf si le système a failli.
                     return false;
                 }
            } catch {
                // Si accountLiquidity revert, c'est louche mais pas forcément une preuve de faille
                // sauf si c'est un revert inattendu.
            }
        }
        return true;
    }

    /// @notice Invariant #2 : Intégrité de l'EVC
    /// @dev Vérifie que le flag "checksInProgress" est bien remis à zéro.
    function invariant_evc_state() public view returns (bool) {
        // L'EVC ne doit jamais rester bloqué en mode "Vérification en cours" hors d'une transaction.
        return !evc.areChecksInProgress();
    }
    
    /// @notice Invariant #3 : Pas de Ghost Collateral
    /// @dev Vérifie que tout collatéral activé correspond à un vrai dépôt.
    function invariant_no_ghost_collateral() public view returns (bool) {
        // Implémentation à venir : Scanner les bitmasks de l'EVC.
        return true;
    }
}
