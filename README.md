# ADShareMounter

This is a ruby script for conveniently managing mount-at-login network drives on OS X from your Active Directory infrastructure.

It utilitizes the Notes section of certain Active Directory groups for information on what to do.

## Client Installation

Install the LaunchAgent property list at /Library/LaunchAgents, then install the script itself at /Library/CLLA/, or wherever else you install your management scripts. If you choose to relocate the script, remember to edit the launchagent plist.

**Note**

This script was written using an adapter architecture to use various backends to communicate with your directory. Currently, it only supports BeyondTrust's PowerBroker Identity Service, Open Edition (pbis). The enterprise edition of pbis may also work, but is untested.

## Server Installation

Hah, there's nothing to install!

## Directory Configuration

### Master Group
The ADShareMounter looks at one group in your Active Directory for a list of all the groups it should read for instructions. That groups is named, by default, "CLLA-All Mac Shares". If you have an access control group for your HR department's shared drive named "HR-GroupShare", you would add that group as a member of "CLLA-All Mac Shares".

### Share Groups
The share groups is where you will write the instructions and provide the share information. You will provide this by putting JSON data in the Notes text box of the group's Properties window.

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

ADShareMounter uses the `mount_smbfs` utility to mount a fileshare. It relies on your client having a valid Kerberos tgt to connect to the fileshare server, so it will not prompt the user for a password at any time. If the connection fails, a warning will be written to the system log file but no message will be presented to the user.

### Variable Substitutions

In the `mountname` and `path` keys above, you can use certain variables to create custom values. Current only %U is supported, which will be substituted for the current logged in user.

### Example JSON

<code>
  {
    "shares" : {
      "comment" : "\"Home\" drive - translates to the H: drive on windows",
      "path" : "smb://myfileserver.foo.edu/Homes/%U",
      "domain" : "FOO"
    }
  }
</code>