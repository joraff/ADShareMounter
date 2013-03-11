# ADShareMounter

This is a ruby script for conveniently managing mount-at-login network drives on OS X from your Active Directory infrastructure. Printer support is planned for the future, and will likely be in a different project.

Simply write some JSON data to go in the Notes section of an active directory group, add your group members, and the client will enumerate those groups and mount the share.

## Client Installation

Install the LaunchAgent property list at /Library/LaunchAgents, then install the project at /Library/CLLA/, or wherever else you install your management scripts. If you choose to relocate the script, remember to edit the launchagent plist.

**Note**

This script was written using an adapter architecture to use various backends to communicate with your directory. Currently, it supports AD plugins that interface with the DirectoryServices frameworks (including the built-in AD plugin) and BeyondTrust's PowerBroker Identity Service, Open Edition (pbis). The enterprise edition of pbis may also work, but is untested.


## Directory Configuration


### Share Groups
The share groups are where you will write the instructions and provide the share information. You will provide this by putting JSON data in the Notes text box of the group's Properties window in AD Users and Computers, or using some other AD attribute editor.

Nesting of share groups *is* supported - groups will be searched recursively for other groups.

The JSON structure is simple: it should contain a single `shares` key whose value can be:

* a string of the uri for the share. 
* an object with the following keys:
  * `path` required - a string of the uri for the share
  * `domain` optional - a domain to prepend to the username (FOO\username@...)
  * `mountname` optional - which folder to create under /Volumes to mount the share on (/Volumes/mountname)
* an array of objects in the same format specified above

If `domain` is omitted, no domain is specified in the connect string and we will attemt to connect to the share using the current username only, i.e. currentuser@server.com/share. 

If `mountname` is omitted, the last folder of the path uri is used to create the mount point. For instance, server.com/Shares/DepartmentFoo will be mounted to /Volumes/DepartmentFoo.

You may add any other keys which will help you in any way. I often add a comment key describing the share.

**Note**

As of PBIS open edition version 7.0.6 there's a problem reading multi-line data from directory attributes. You'll have to "minify" your JSON to fit on one line when pasting it into the Notes box.

## How it works

When launched, it will enumerate the directory groups that the current user is a member of. It then tries to read the "info" attribute (which is populated by the Notes textbox in the AD Users and Computers GUI) of each group for JSON data describing the share.

It will then try to mount the share as described by using the mount tool (`mount -t smbfs`) using SSO (kerberos) credentials. Password prompting is not supported and is not planned: the user must have a kerberos tgt.


### Variable Substitutions

In the `mountname` and `path` keys above, you can use certain variables to create custom values. Current only %U is supported, which will be substituted for the current logged in user.

### Example JSON


    {
      "shares" : {
        "comment" : "'Home' drive - translates to the H: drive on windows",
        "path" : "smb://myfileserver.foo.edu/Homes/%U",
        "domain" : "FOO"
      }
    }