# The single place the Microsoft Store packaging gets its identity from.
#
# Three of these four values are NOT ours to choose: they come from Partner Center, after the
# product name is reserved. The values below are working placeholders so the package can be built,
# installed and tested locally; they are marked so that nobody ships them.
#
#   PackageName          Partner Center -> Product identity -> Package/Identity/Name
#                        (convention: Publisher.Name, e.g. SudeepAudioLLP.SASur)
#   Publisher            Partner Center -> Product identity -> Package/Identity/Publisher
#                        e.g. CN=Sudeep Audio.com LLP for a company account
#   PublisherDisplayName Partner Center -> Account settings -> Publisher display name
#   Version              ours, and the Store line's own number: four parts, the last always 0
#                        (Partner Center reserves the revision field), increasing every submission.
#
# The Publisher value must also be the subject of the certificate that signs the package. For a
# Store submission that is a formality - the Store re-signs and ignores our signature - but it is
# what lets the package be installed and tested here first.
@{
    PackageName          = 'SudeepAudioLLP.SASur'   # PLACEHOLDER - replace from Partner Center
    Publisher            = 'CN=Sudeep Audio.com LLP' # PLACEHOLDER - replace from Partner Center
    PublisherDisplayName = 'Sudeep Audio.com LLP'    # PLACEHOLDER - replace from Partner Center
    Version              = '1.1.0.0'                 # the Store line: stamped, never inherited
}
