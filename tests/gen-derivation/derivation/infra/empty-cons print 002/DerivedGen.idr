module DerivedGen

import AlternativeCore
import PrintDerivation

import Data.Vect

%default total

%language ElabReflection

%runElab printDerived @{EmptyCons} $ Fuel -> (n : Nat) -> (a : Type) -> Gen MaybeEmpty (Vect n a)
