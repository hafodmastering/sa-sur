# The single place the Microsoft Store packaging gets its identity from.
#
# These four values came from Partner Center -> Product identity, after the product name was
# reserved. They are NOT ours to choose and the manifest must match them exactly.
#
#   PackageName          Partner Center -> Product identity -> Package/Identity/Name
#   Publisher            Partner Center -> Product identity -> Package/Identity/Publisher
#                        Generated at reservation: CN=<guid> for this account, not the company name.
#   PublisherDisplayName Partner Center -> Product identity -> Publisher display name
#   Version              ours: the product version in four parts, the last always 0 (Partner
#                        Center reserves the revision field), increasing every submission. Since
#                        1.2.0 this is the same number as every other channel - 1.2.0 written where
#                        four parts are required. See docs/RELEASE.md.
#
# The Publisher value is also the subject of any certificate that signs the package for local
# testing. For a Store submission the signature is a formality - the Store re-signs - but the
# resulting package family name is a check that the identity is right: it must match the PFN
# Partner Center reports for the product (SudeepAudio.SA-Sur_sc5pm0db8zg9r when this was written).
@{
    PackageName          = 'SudeepAudio.SA-Sur'
    Publisher            = 'CN=5A16320F-B976-49A4-9FDF-FEA82A152D92'
    PublisherDisplayName = 'Sudeep Audio'
    Version              = '1.2.0.0'
}
