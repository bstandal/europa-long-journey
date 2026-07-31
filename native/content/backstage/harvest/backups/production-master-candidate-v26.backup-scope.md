# Harvest v26 local backup scope

Status: `HOST_ONLY_COPY_NOT_ACCEPTED_AS_PRODUCTION_BACKUP`

The exact v26 candidate has one byte-identical backstage copy on the same
Mac. `fdesetup status` reported `FileVault is On` before the copy was made, so
the host reports that the same-volume copy is covered by its existing disk
encryption. This observation is not independent verification of an encrypted
backup mechanism. The source and copy are each 5,860,864 bytes with
SHA-256 `e00eebcac9c20b7cd4c30193ea21bc7f032981817840cb85694298240d0618ca`.

`tmutil destinationinfo` reported no configured Time Machine destination.
This copy may protect against an accidental single-file change. It is not an
independent-device or independent-volume backup, does not protect against loss
or failure of this Mac, and does not satisfy the production backup gate.
