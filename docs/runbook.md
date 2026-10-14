# Runbook - DRAFT (Member 3 section, Day 1)

Status: DRAFT. Steps marked TBC must be confirmed on the real system and release before anyone relies on them. All data is DEMO / SYNTHETIC.

## 1. Prerequisites

- [ ] SAP BTP trial account with an ABAP environment instance that is running
- [ ] VS Code with the SAP ABAP Development Tools extension, or Eclipse ADT as the fallback
- [ ] Destination created and added to the workspace
- [ ] A package where probe objects may be created, and a transport request if one is required: TBC
- [ ] Two test users with different roles (for example one developer and one reviewer): TBC

## 2. Connect (record the exact steps that worked)

1. Create a destination (HTTP, system URL): TBC
2. Add the destination as a workspace folder and sign in: TBC
3. Confirm packages and objects appear in the Explorer: TBC

## 3. Probe steps (repeat in this order, record results in docs/feasibility-note.md)

| Step | What to do | What to check | Done |
|---|---|---|---|
| 1 | Create a CDS view entity on a simple table, then a service definition and a service binding | A read returns data. OData version noted | [ ] |
| 2 | Create a managed RAP business object with one action and one validation | Both activate and run once | [ ] |
| 3 | Read the current user inside the action | The user ID is returned or stored. Method used: TBC (check SAP Help Portal for your release) | [ ] |
| 4 | Add an authorization check to the action | Allowed user passes, denied user gets a backend error | [ ] |
| 5 | Add ETag or lock handling and change the same record from two sessions | Second save is rejected with a conflict | [ ] |
| 6 | Try the import path options in feasibility-note.md section 5 | Which one works, which one is blocked | [ ] |

For every step write down: the objects created, the transport ID, and the exact error text if anything failed.

## 4. Reset

How to remove or re-create the probe objects and test data: TBC

## 5. Known blockers

See docs/feasibility-note.md section 6.