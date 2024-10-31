#! /bin/bash
# A modification of Dean Clatworthy's deploy script as found here: https://github.com/deanc/wordpress-plugin-git-svn
# The difference is that this script lives in the plugin's git repo & doesn't require an existing SVN repo.

# main config
PLUGINSLUG="mz-mobilize-america-interface"
CURRENTDIR=`pwd`
MAINFILE="mz-mobilize-america.php" # this should be the name of your main php file in the wordpress plugin

# git config
GITPATH="$CURRENTDIR/" # this file should be in the base of your git repository

# svn config
SVNPATH="/tmp/$PLUGINSLUG" # path to a temp SVN repo. No trailing slash required and don't add trunk.
SVNURL="http://plugins.svn.wordpress.org/mz-mobilize-america-interface" # Remote SVN repo on wordpress.org, with no trailing slash
SVNUSER="mikeill" # your svn username


# Let's begin...
echo ".........................................."
echo 
echo "Preparing to deploy wordpress plugin"
echo 
echo ".........................................."
echo 

# Check if subversion is installed before getting all worked up
#if [ $(dpkg-query -W -f='${Status}' subversion 2>/dev/null | grep -c "ok installed") != "1" ]
#then
#	echo "You'll need to install subversion before proceeding. Exiting....";
#	exit 1;
#fi

# Check version in readme.txt is the same as plugin file after translating both to unix line breaks to work around grep's failure to identify mac line breaks
NEWVERSION1=`grep "^Stable tag:" $GITPATH/readme.txt | awk -F' ' '{print $NF}'`
echo "readme.txt version: $NEWVERSION1"
NEWVERSION2=`grep "^ \* Version:" $GITPATH/$MAINFILE | awk -F' ' '{print $NF}'`
echo "$MAINFILE version: $NEWVERSION2"

if [ "$NEWVERSION1" != "$NEWVERSION2" ]; then echo "Version in readme.txt & $MAINFILE don't match. Exiting...."; exit 1; fi

echo "Versions match in readme.txt and $MAINFILE. Let's proceed..."

if git show-ref --tags --quiet --verify -- "refs/tags/$NEWVERSION1"
	then 
		echo "Version $NEWVERSION1 already exists as git tag. Exiting...."; 
		exit 1; 
	else
		echo "Git version does not exist. Let's proceed..."
fi

cd $GITPATH
echo -e "Enter a commit message for this new version: \c"
read COMMITMSG
git commit -am "$COMMITMSG"

echo "Tagging new version in git"
git tag -a "$NEWVERSION1" -m "Tagging version $NEWVERSION1"

echo "Pushing latest commit to origin, with tags"
git push origin master
git push origin master --tags

echo 
echo "Creating local copy of SVN repo ..."
svn co $SVNURL $SVNPATH --depth empty 

# for zsh disable prompt when removing wildcard
setopt rmstarsilent

echo "Clearing svn repo so we can overwrite it"
rm -rf $SVNPATH/trunk/*

echo "Exporting the HEAD of master from git to the trunk of SVN"
git checkout-index -a -f --prefix=$SVNPATH/trunk/

echo "Changing directory to SVN path"
cd $SVNPATH
echo "Update tags directory."
svn update trunk  --depth empty

echo "Ignoring github specific files and deployment script"
svn propset svn:ignore "
README.md
node_modules
tests
assets
wpassets
.DS_Store
.gitmodules
.babelrc
package.json
package-lock.json
bin/install-wp-tests.sh
phpunit.xml.dist
phpcs.ruleset.xml
phpcs.xml.dist
.git
*.log
*.sh
webpack.config.js
.gitignore" "$SVNPATH/trunk/"

echo "Changing directory to SVN and committing to trunk"
cd $SVNPATH/trunk/

echo "Install production composer deps"
# This requires jq: https://www.howtogeek.com/529219/how-to-parse-json-files-on-the-linux-command-line-with-jq/
if [ -s './composer.json' ]; then
    #Detect if there are composer dependencies
    echo "-Check composer dependencies..."
    if [ "$(uname)" == "Darwin" ]; then
		dep=$(cat "./composer.json" | jq 'has("require")')
	else
		dep=$(cat "./composer.json" | jq 'has(".require")')
	fi

    if [ "$dep" == 'true' ]; then
        echo "-Download clean composer dependencies..."
        composer update --no-dev # &> /dev/null
        echo "-Run composer dumpautoload -o"
        composer dumpautoload -o
    else
        rm -rf ./composer.json
    fi
fi 
# Add all new files that are not set to be ignored
echo "Do the file adding"
svn status | grep -v "^.[ \t]*\..*" | grep "^?" | awk '{print $2}' | xargs svn add
echo "Commit"
svn commit --username=$SVNUSER -m "$COMMITMSG"
cd $SVNPATH
svn copy trunk/ tags/$NEWVERSION1/
cd $SVNPATH/tags/$NEWVERSION1
svn commit --username=$SVNUSER -m "Tagging version $NEWVERSION1"

echo "Returning home"
cd $CURRENTDIR

echo "Removing temporary directory $SVNPATH"
rm -fr $SVNPATH/

echo "*** Deployment Complete ***"
