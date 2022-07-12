===========
Limitations
===========

.. todo to add links to `design/...` sections

Temporary design decisions
==========================

Signature of derived generator
------------------------------

Fuel pattern
````````````

- explicit fuel pattern of derived gens for totality because ``Gen`` monad is only finite

- explicit fuel pattern is required even for non-recursive data types

Regular parameters
``````````````````

- all params of derived generators must

  - be omega (runtime)
  - have the same name as such parameter in the original type

Auto parameters
```````````````

- only of ``Gen`` type is supported to be in ``auto``-parameters of the derived generators

- external ``Gen`` (passed as ``auto``-parameter) must have the signature of generated one (i.e. fuel pattern, omega, names as in the type, etc.)

``Type`` and higher-kinded type parameters
``````````````````````````````````````````

- only types with type parameters in covariant position are supported

- each parameter of type ``Type`` require a generator of this type
  (disregarding whether this type is used as a value in the generated type or not)

- if parameter of type ``Type`` is generated,
  then a special generator with signature ``Fuel -> Gen (a : Type ** Gen a)`` is required in the list of external generators

- higher-kinded parameters (i.e. those of a function type which returns ``Type``) are not supported

Structure of derived generator
------------------------------

- now all derived subgenerators needed for the current type are generated as local functions inside the derived generator function
  even if there are some common generators between different derivation tasks

To be fixed/reworked
====================

- speed of derivation
- polymorphism over types, including external gens over quantified types
- no external ``DecEq``'s yet
- least-effort cons derivator: no support of ordering depending on externals
- GADT structure does not influence on the ordering of cons params generation
- no support for additional ``auto`` arguments of derived gens (even if they are needed for the generated data)
- only constructors (and bare variables) are supported on the RHS of GADTs constructors
