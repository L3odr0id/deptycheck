||| Several tactics for derivation of particular generators for a constructor regarding to how they use externals
module Test.DepTyCheck.Gen.Auto.Core.ConsDerive

import public Control.Monad.State

import public Data.Either

import public Decidable.Equality

import public Test.DepTyCheck.Gen.Auto.Derive

import public Test.DepTyCheck.Gen.Auto.Util.DepPerm

%default total

-------------------------------------------------
--- Derivation of a generator for constructor ---
-------------------------------------------------

--- Interface ---

public export
interface ConstructorDerivator where
  consGenExpr : CanonicGen m => GenSignature -> (con : Con) -> (given : SortedSet $ Fin con.args.length) -> (fuel : TTImp) -> m TTImp

--- Particular tactics ---

||| "Non-obligatory" means that some present external generator of some type
||| may be ignored even if its type is really used in a generated data constructor.
namespace NonObligatoryExts

  -- This data definition should have been inside a `LeastEffort` instance, but addition of some line makes it to stop to typecheck
  record TypeApp (0 con : Con) where
    constructor MkTypeApp
    type : TypeInfo
    argTypes : Vect type.args.length $ Either (Fin con.args.length) TTImp

  ||| Least-effort non-obligatory tactic is one which *does not use externals* during taking a decision on the order.
  ||| It uses externals if decided order happens to be given by an external generator, but is not obliged to use any.
  ||| It is seemingly most simple to implement, maybe the fastest and
  ||| fits well when external generators are provided for non-dependent types.
  export
  [LeastEffort] ConstructorDerivator where
    consGenExpr sig con givs fuel = do

      -------------------------------------------------------------
      -- Prepare intermediate data and functions using this data --
      -------------------------------------------------------------

      -- Get file position of the constructor definition (for better error reporting)
      let conFC = getFC con.type

      -- Build a map from constructor's argument name to its index
      let conArgIdxs = SortedMap.fromList $ mapI' con.args $ \idx, arg => (argName arg, idx)

      -- Analyse that we can do subgeneration for each constructor argument
      -- Fails using `Elaboration` if the given expression is not an application to a type constructor
      let analyseTypeApp : TTImp -> m $ TypeApp con
          analyseTypeApp expr = do
            let (lhs, args) = unAppAny expr
            ty <- case lhs of
              IVar _ lhsName     => try .| getInfo' lhsName -- TODO to support `lhsName` to be a type parameter of type `Type`
                                        .| failAt (getFC lhs) "Only applications to non-polymorphic type constructors are supported at the moment"
              IPrimVal _ (PrT t) => pure $ typeInfoForPrimType t
              IType _            => pure typeInfoForTypeOfTypes
              lhs                => failAt (getFC lhs) "Only applications to a name is supported, given \{lhs}"
            let Yes lengthCorrect = decEq ty.args.length args.length
              | No _ => failAt (getFC lhs) "INTERNAL ERROR: wrong count of unapp when analysing type application"
            pure $ MkTypeApp ty $ rewrite lengthCorrect in Vect.fromList args <&> \arg => case getExpr arg of
              expr@(IVar _ n) => mirror . maybeToEither expr $ lookup n conArgIdxs
              expr            => Right expr

      -- Compute left-to-right need of generation when there are non-trivial types at the left
      argsTypeApps <- for .| Vect.fromList con.args .| analyseTypeApp . type

      -- Decide how constructor arguments would be named during generation
      let bindNames : Vect (con.args.length) String
          bindNames = flip mapWithPos .| fromList con.args .| \idx, arg => case argName arg of
                        UN (Basic n) => n
                        n            => (if contains idx givs then id else ("^bnd^" ++)) $ show n

      -- Derive constructor calling expression for given order of generation
      let genForOrder : List (Fin con.args.length) -> m TTImp
          genForOrder = map (`apply` callCons) . evalStateT givs . foldlM genForOneArg id where

            -- ... state is the set of arguments that are already present (given or generated)
            genForOneArg : forall m.
                           CanonicGen m =>
                           MonadState (SortedSet $ Fin con.args.length) m =>
                           (TTImp -> TTImp) -> (gened : Fin con.args.length) -> m $ TTImp -> TTImp
            genForOneArg leftExprF genedArgIdx = do

              -- Acquire the set of arguments that are already present
              presentArguments <- get

              -- Check that those argument that we need to generate is not already present
              let False = contains genedArgIdx presentArguments
                | True => pure leftExprF

              -- Get info for the `genedArgIdx`
              let genedArg = Vect.index genedArgIdx argsTypeApps

              -- Filter arguments classification according to the set of arguments that are left to be generated;
              -- Those which are `Right` are given, those which are `Left` are needs to be generated.
              let depArgs : Vect _ $ Either _ _ := genedArg.argTypes <&> \case
                Right expr => Right expr
                Left i     => if contains i presentArguments then Right $ var $ argName $ index' con.args i else Left i

              -- Determine which arguments will be on the left of dpair in subgen call, in correct order
              let subgeneratedArgIdxs = mapMaybe getLeft $ toList depArgs

              -- Make sure generated arguments will not be generated again
              modify $ insert genedArgIdx . union (fromList subgeneratedArgIdxs)

              -- Form a task for subgen
              let (subgivensLength ** subgivens) = mapMaybe (\(ie, idx) => (idx,) <$> getRight ie) $ depArgs `zip` allFins'
              let subsig : GenSignature := MkGenSignature genedArg.type $ fromList $ fst <$> toList subgivens
              let Yes Refl = decEq subsig.givenParams.size subgivensLength
                | No _ => fail "INTERNAL ERROR: error in given params set length computation"

              -- Form an expression to call the subgen
              subgenCall <- callGen subsig fuel $ snd <$> subgivens

              -- Form an expression of binding the result of subgen
              let genedArg:::subgeneratedArgs = genedArgIdx:::subgeneratedArgIdxs <&> bindVar . flip Vect.index bindNames
              let bindSubgenResult = foldr (\l, r => var `{Builtin.DPair.MkDPair} .$ l .$ r) genedArg subgeneratedArgs

              -- Form an expression of the RHS of a bind; simplify lambda if subgeneration result type does not require pattern matching
              let bindRHS = \cont => case bindSubgenResult of
                                       IBindVar _ n => lam (MkArg MW ExplicitArg (Just $ UN $ Basic n) implicitFalse) cont
                                       _            => `(\ ~bindSubgenResult => ~cont)

              -- Chain the subgen call with a given continuation
              pure $ \cont => leftExprF `(~subgenCall >>= ~(bindRHS cont))

            callCons : TTImp
            callCons = do
              let constructorCall = callCon con $ bindNames <&> varStr
              let wrapImpls : Nat -> TTImp
                  wrapImpls Z     = constructorCall
                  wrapImpls (S n) = var `{Builtin.DPair.MkDPair} .$ implicitTrue .$ wrapImpls n
              let consExpr = wrapImpls $ sig.targetType.args.length `minus` sig.givenParams.size
              `(Prelude.pure {f=Test.DepTyCheck.Gen.Gen} ~consExpr)

      -- Get dependencies of constructor's arguments
      rawDeps <- argDeps con.args
      let deps = downmap ((`difference` givs) . mapIn weakenToSuper) rawDeps

      -------------------------------------------------
      -- Left-to-right generation phase (2nd phase) ---
      -------------------------------------------------

      -- Determine which arguments need to be generated in a left-to-right manner
      let (leftToRightArgsTypeApp, leftToRightArgs) = unzip $ filter (\((MkTypeApp _ as), _) => any isRight as) $ toListI argsTypeApps

      --------------------------------------------------------------------------------
      -- Preparation of input for the left-to-right phase (1st right-to-left phase) --
      --------------------------------------------------------------------------------

      -- Acquire those variables that appear in non-trivial type expressions, i.e. those which needs to be generated before the left-to-right phase
      let preLTR = leftToRightArgsTypeApp >>= \(MkTypeApp _ as) => rights (toList as) >>= toList . allVarNames
      let preLTR = SortedSet.fromList $ mapMaybe (flip lookup conArgIdxs) preLTR

      -- Find rightmost arguments among `preLTR`
      let depsLTR = SortedSet.fromList $
                      mapMaybe (\(ds, idx) => whenT .| contains idx preLTR && null ds .| idx) $
                        toListI $ deps <&> intersection preLTR

      ---------------------------------------------------------------------------------
      -- Main right-to-left generation phase (3rd phase aka 2nd right-to-left phase) --
      ---------------------------------------------------------------------------------

      -- Arguments that no other argument depends on
      let rightmostArgs = fromFoldable {f=Vect _} allFins' `difference` (givs `union` concat deps)

      ---------------------------------------------------------------
      -- Manage different possible variants of generation ordering --
      ---------------------------------------------------------------

      -- Prepare info about which arguments are independent and thus can be ordered arbitrarily
      let disjDeps = disjointDepSets rawDeps givs

      -- Acquire order(s) in what we will generate arguments
      let allOrders = do
        leftmost  <- indepPermutations' disjDeps depsLTR
        rightmost <- indepPermutations' disjDeps rightmostArgs
        pure $ leftmost ++ leftToRightArgs ++ rightmost

      map callOneOf $ traverse genForOrder allOrders

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
    consGenExpr sig con givs fuel = do
      ?cons_body_besteff_nonoblig_rhs

||| "Obligatory" means that is some external generator is present and a constructor has
||| an argument of a type which is generated by this external generator, it must be used
||| in the constructor's generator.
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
    consGenExpr sig con givs fuel = do
      ?cons_body_obl_ff_rhs

  export
  [DecEqConflicts] ConstructorDerivator where
    consGenExpr sig con givs fuel = do
      ?cons_body_obl_deceq_rhs
