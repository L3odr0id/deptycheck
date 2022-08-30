||| Derivation of the outer layer of a constructor-generating function, performing GADT indices check of given arguments.
module Test.DepTyCheck.Gen.Auto.Core.ConsEntry

import public Control.Monad.State.Tuple

import public Decidable.Equality

import public Test.DepTyCheck.Gen.Auto.Core.ConsDerive
import public Test.DepTyCheck.Gen.Auto.Core.Util

%default total

-------------------------------------------------
--- Derivation of a generator for constructor ---
-------------------------------------------------

--- Entry function ---

export
canonicConsBody : ConstructorDerivator => CanonicGen m => GenSignature -> Name -> Con -> m $ List Clause
canonicConsBody sig name con = do

  -- Get file position of the constructor definition (for better error reporting)
  let conFC = getFC con.type

  -- Normalise the types in constructor; expand functions that are used as types, if possible
  con <- normaliseCon con

  -- Acquire constructor's return type arguments
  let (conRetTy, conRetTypeArgs) = unAppAny con.type
  conRetTypeArgs <- for conRetTypeArgs $ \case -- resembles similar management from `Entry` module; they must be consistent
    PosApp e     => pure e
    NamedApp _ _ => failAt conFC "Named implicit applications (like to `\{show conRetTy}`) are not supported yet"
    AutoApp _    => failAt conFC "Auto-implicit applications (like to `\{show conRetTy}`) are not supported yet"
    WithApp _    => failAt conFC "Unexpected `with` application to `\{show conRetTy}` in a constructor's argument"

  -- Match lengths of `conRetTypeArgs` and `sig.targetType.args`
  let Yes conRetTypeArgsLengthCorrect = conRetTypeArgs.length `decEq` sig.targetType.args.length
    | No _ => failAt conFC "INTERNAL ERROR: length of the return type does not equal to the type's arguments count"

  let conRetTypeArg : Fin sig.targetType.args.length -> TTImp
      conRetTypeArg idx = index' conRetTypeArgs $ rewrite conRetTypeArgsLengthCorrect in idx

  -- Determine names of the arguments of the constructor (as a function)
  let conArgNames = fromList $ (.name) <$> con.args

  -- For given arguments, determine whether they are
  --   - just a free name
  --   - repeated name of another given parameter (need of `decEq`)
  --   - (maybe, deeply) constructor call (need to match)
  --   - function call on a free param (need to use "inverted function" filtering trick)
  --   - something else (cannot manage yet)
  deepConsApps <- for sig.givenParams.asVect $ \idx => do
    let argExpr = conRetTypeArg idx
    Just analysed <- analyseDeepConsApp True conArgNames argExpr
      | Nothing => failAt conFC "Argument #\{show idx} is not supported yet (argument expression: \{show argExpr})"
    pure analysed

  -- Acquire LHS bind expressions for the given parameters
  -- Determine pairs of names which should be `decEq`'ed
  let getAndInc : forall m. MonadState Nat m => m Nat
      getAndInc = get <* modify S
  ((givenConArgs, decEqedNames, _), bindExprs) <-
    runStateT (empty, empty, 0) {stateType=(SortedSet String, SortedSet (String, String), Nat)} {m} $
      for deepConsApps $ \(appliedNames ** bindExprF) => do
        renamedAppliedNames <- for appliedNames.asVect $ \(name, typeDetermined) => case name of
          UN (Basic name) => if not (cast typeDetermined) && contains name !get
            then do
              -- I'm using a name containing chars that cannot be present in the code parsed from the Idris frontend
              let substName = "to_be_deceqed^^" ++ name ++ show !getAndInc
              modify $ insert (name, substName)
              pure $ \alreadyMatchedRenames => bindVar $ if contains substName alreadyMatchedRenames then name else substName
            else modify (insert name) $> const (bindVar name)
          badName => failAt conFC "Unsupported name `\{show badName}` of a parameter used in the constructor"
        let _ : Vect appliedNames.length $ SortedSet String -> TTImp = renamedAppliedNames
        pure $ \alreadyMatchedRenames => bindExprF $ \idx => index idx renamedAppliedNames $ alreadyMatchedRenames
  let bindExprs = \alreadyMatchedRenames => bindExprs <&> \f => f alreadyMatchedRenames

  -- Build a map from constructor's argument name to its index
  let conArgIdxs = SortedMap.fromList $ mapI' con.args $ \idx, arg => (argName arg, idx)

  -- Determine indices of constructor's arguments that are given
  givenConArgs <- for givenConArgs.asList $ \givenArgNameStr => do
    let Just idx = lookup (UN $ Basic givenArgNameStr) conArgIdxs
      | Nothing => failAt conFC "INTERNAL ERROR: calculated given `\{givenArgNameStr}` is not found in an arguments list of the constructor"
    pure idx

  -- Equalise index values which must be propositionally equal to some parameters
  -- NOTE: Here I do all `decEq`s in a row and then match them all against `Yes`.
  --       I could do this step by step and this could be more effective in large series.
  let deceqise : (lhs : Vect sig.givenParams.asList.length TTImp -> TTImp) -> (rhs : TTImp) -> Clause
      deceqise lhs rhs = step lhs empty $ orderLikeInCon decEqedNames where

        step : (withlhs : Vect sig.givenParams.asList.length TTImp -> TTImp) ->
               (alreadyMatchedRenames : SortedSet String) ->
               (left : List (String, String)) ->
               Clause
        step withlhs matched [] = PatClause EmptyFC .| withlhs (bindExprs matched) .| rhs
        step withlhs matched ((orig, renam)::rest) =
          WithClause EmptyFC (withlhs $ bindExprs matched) MW
            `(Decidable.Equality.decEq ~(varStr renam) ~(varStr orig))
            Nothing []
            [ -- happy case
              step ((.$ `(Prelude.Yes Builtin.Refl)) . withlhs) (insert renam matched) rest
            , -- empty case
              PatClause EmptyFC .| withlhs (bindExprs matched) .$ `(Prelude.No _) .| `(empty)
            ]

        -- Order pairs by the first element like they are present in the constructor's signature
        orderLikeInCon : Foldable f => f (String, String) -> List (String, String)
        orderLikeInCon = do
          let conArgStrNames = mapMaybe argStrName con.args
          let conNameToIdx : SortedMap _ $ Fin conArgStrNames.length := fromList $ mapI' conArgStrNames $ flip (,)
          let [AsInCon] Ord (String, String) where
                compare (origL, renL) (origR, renR) = comparing (flip lookup conNameToIdx) origL origR <+> compare renL renR
          SortedSet.toList . foldl (flip insert) (empty @{AsInCon})
          where
            argStrName : NamedArg -> Maybe String
            argStrName $ MkArg {name=UN (Basic n), _} = Just n
            argStrName _                              = Nothing

  -- Form the declaration cases of a function generating values of particular constructor
  let fuelArg = "^cons_fuel^" -- I'm using a name containing chars that cannot be present in the code parsed from the Idris frontend
  pure $
    -- Happy case, given arguments conform out constructor's GADT indices
    [ deceqise (callCanonic sig name $ bindVar fuelArg) !(consGenExpr sig con .| fromList givenConArgs .| varStr fuelArg) ]
    ++ if all isSimpleBindVar $ bindExprs empty then [] {- do not produce dead code if the happy case handles everything already -} else
      -- The rest case, if given arguments do not conform to the current constructor then return empty generator
      [ callCanonic sig name implicitTrue (replicate _ implicitTrue) .= `(empty) ]
