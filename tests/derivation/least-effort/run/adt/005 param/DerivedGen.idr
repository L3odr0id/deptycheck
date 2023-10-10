module DerivedGen

import RunDerivedGen

%default total

%language ElabReflection

data X : Nat -> Type where
  MkX : X n

{n : Nat} -> Show (X n) where
  show MkX = "MkX : X \{show n}"

checkedGen : Fuel -> (n : Nat) -> Gen MaybeEmpty (X n)
checkedGen = deriveGen @{LeastEffort}

main : IO ()
main = runGs
  [ G $ \fl => checkedGen fl 0
  , G $ \fl => checkedGen fl 3
  ]
