||| Several tactics for derivation of particular generators for a constructor regarding to how they use externals
module Test.DepTyCheck.Gen.Auto.Core.Cons

import public Test.DepTyCheck.Gen.Auto.Derive

import public Test.DepTyCheck.Gen.Auto.Util.Collections

%default total

-----------------------------------------
--- Utility functions and definitions ---
-----------------------------------------

--- Expressions generation utils ---

defArgNames : {sig : GenSignature} -> Vect sig.givenParams.asList.length String
defArgNames = sig.givenParams.asVect <&> show . name . index' sig.targetType.args

export %inline
canonicDefaultLHS : GenSignature -> Name -> (fuel : String) -> TTImp
canonicDefaultLHS sig n fuel = callCanonic sig n .| bindVar fuel .| bindVar <$> defArgNames

export %inline
canonicDefaultRHS : GenSignature -> Name -> (fuel : TTImp) -> TTImp
canonicDefaultRHS sig n fuel = callCanonic sig n fuel .| varStr <$> defArgNames

-------------------------------------------------
--- Derivation of a generator for constructor ---
-------------------------------------------------

--- Interface ---

public export
interface ConstructorDerivator where
  canonicConsBody : CanonicGen m => GenSignature -> Name -> Con -> m $ List Clause

--- Particular tactics ---

||| "Non-obligatory" means that some present external generator of some type
||| may be ignored even if its type is really used in a generated data constructor.
namespace NonObligatoryExts

  ||| Leat effort non-obligatory tactic is one which *does not use externals* during taking a decision on the order.
  ||| It uses externals if decided order happens to be given by an external generator, but is not obliged to use any.
  ||| It is seemingly most simple to implement, maybe the fastest and
  ||| fits well when external generators are provided for non-dependent types.
  export
  [LeastEffort] ConstructorDerivator where
    canonicConsBody sig name con = do

      -- Get dependencies of constructor's arguments
      deps <- argDeps con.args
      let weakenedDeps : Vect _ $ SortedSet $ Fin _ := flip downmapI deps $ \_ => mapIn weakenToSuper

      -- Arguments that no other argument depends on
      let kingArgs = fromFoldable (allFins' _) `difference` concat weakenedDeps

      -- Acquire order(s) in what we will generate arguments
      -- TODO to permute independent groups of arguments independently
      let allKingsOrders = allPermutations kingArgs

      let fuelArg = "fuel_cons_arg"

      let genForKingsOrder : List (Fin con.args.length) -> m TTImp
          genForKingsOrder kings = ?genForKingsOrder_rhs

      gensForKingsOrders <- traverse genForKingsOrder $ forget allKingsOrders

      pure [ canonicDefaultLHS sig name fuelArg .= callOneOf gensForKingsOrders ]

  ||| Best effort non-obligatory tactic tries to use as much external generators as possible
  ||| but discards some there is a conflict between them.
  ||| All possible non-conflicting layouts may be produced in the generated values list.
  |||
  ||| E.g. when we have external generators ``(a : _) -> (b : T ** C a b)`` and ``(b : T ** D b)`` and
  ||| a constructor of form ``C a b -> D b -> ...``, we can use values from both pairs
  ||| ``(a : _) -> (b : T ** C a b)`` with ``(b : T) -> D b`` and
  ||| ``(a : _) -> (b : T) -> C a b`` with ``(b : T ** D b)``,
  ||| i.e. to use both of external generators to form the generated values list
  ||| but not obligatorily all the external generators at the same time.
  export
  [BestEffort] ConstructorDerivator where
    canonicConsBody sig name con = do
      let fuelArg = "fuel_cons_arg"
      pure [ canonicDefaultLHS sig name fuelArg .= ?cons_body_besteff_nonoblig_rhs ]

||| "Obligatory" means that is some external generator is present and a constructor has
||| an argument of a type which is generated by this external generator, it must be used
||| in the constuctor's generator.
|||
||| Dependent types are important here, i.e. generator ``(a : _) -> (b ** C a b)``
||| is considered to be a generator for the type ``C``.
||| The problem with obligatory generators is that some external generators may be incompatible.
|||
|||   E.g. once we have ``(a : _) -> (b ** C a b)`` and ``(a ** b ** C a b)`` at the same time,
|||   once ``C`` is used in the same constructor, we cannot guarantee that we will use both external generators.
|||
|||   The same problem is present once we have external generators for ``(a : _) -> (b : T ** C a b)`` and ``(b : T ** D b)`` at the same time,
|||   and both ``C`` and ``D`` are used in the same constructor with the same parameter of type ``T``,
|||   i.e. when constructor have something like ``C a b -> D b -> ...``.
|||
|||   Notice, that this problem does not arise in constructors of type ``C a b1 -> D b2 -> ...``
|||
||| In this case, we cannot decide in general which value of type ``T`` to be used for generation is we have to use both generators.
||| We can either fail to generate a value for such constructor (``FailFast`` tactic),
||| or alternatively we can try to match all the generated values of type ``T`` from both generators
||| using ``DecEq`` and leave only intersection (``DecEqConflicts`` tactic).
namespace ObligatoryExts

  export
  [FailFast] ConstructorDerivator where
    canonicConsBody sig name con = do
      let fuelArg = "fuel_cons_arg"
      pure [ canonicDefaultLHS sig name fuelArg .= ?cons_body_obl_ff_rhs ]

  export
  [DecEqConflicts] ConstructorDerivator where
    canonicConsBody sig name con = do
      let fuelArg = "fuel_cons_arg"
      pure [ canonicDefaultLHS sig name fuelArg .= ?cons_body_obl_deceq_rhs ]
