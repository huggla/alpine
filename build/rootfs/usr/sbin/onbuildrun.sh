#!/bin/sh

removeEmptyDirs(){
   local dir="$1"
   local subdirs="$(find "$dir" -maxdepth 1 -mindepth 1 -type d)"
   local subdir=""
   for subdir in $subdirs
   do
      removeEmptyDirs "$subdir"
   done
   local childCount="$(find "$dir" -maxdepth 1 -mindepth 1 | wc -l)"
   if [ "$dir" != "/" ] && [ "$childCount" == "0" ] && ! (echo " $MAKEDIRS " | grep -q " ${dir#/finalfs} ")
   then
      rm -rf "$dir"
   fi
}

exec > /build.log 2>&1

set -ex +fam
if [ "${IMAGETYPE#*content}" != "$IMAGETYPE" ] && [ -z "$DESTDIR" ]
then
   DESTDIR="/content"
fi
if [ -n "$ADDREPOS" ]
then
   for repo in $ADDREPOS
   do
      echo $repo >> /etc/apk/repositories
   done
fi
cd /finalfs
rm -rf environment
getfacl -R . > /tmp/init-permissions.txt
tar -xp -f /environment/onbuild.tar.gz -C /tmp
if [ -n "$RUNDEPS" ]
then
   if [ -n "$EXCLUDEDEPS" ] || [ -n "$EXCLUDEAPKS" ]
   then
      cd /excludefs
      apk --repositories-file /etc/apk/repositories --keys-dir /etc/apk/keys --no-cache --initramfs-diskless-boot --clean-protected --root /excludefs add --quiet --initdb $EXCLUDEDEPS $EXCLUDEAPKS
      if [ -n "$EXCLUDEDEPS" ]
      then
         excludeFilesDeps="$(apk --no-cache --quiet --root /excludefs info --depends $EXCLUDEDEPS | xargs apk --no-cache --quiet --root /excludefs info --contents)"
      fi
      excludeFilesApks="$(apk --no-cache --quiet --root /excludefs info --contents $EXCLUDEAPKS)"
      excludeFiles="$(echo ${excludeFilesDeps}${excludeFilesApks} | grep -v '^$' | sort -u -)"
      for file in $excludeFiles
      do
         if find "$file" -maxdepth 0 ! -path 'var/cache/*' ! -path 'tmp/*' | grep -q -e .
         then
            if [ -L "$file" ]
            then
               (echo -n "/$file>" && readlink "$file") >> /tmp/onbuild/exclude.filelist
            elif [ -f "$file" ]
            then
               md5sum "$file" | awk '{first=$1; $1=""; print $0">"first}' | sed 's|^ |/|' >> /tmp/onbuild/exclude.filelist || exit 1
            fi
         fi
      done
      rm -rf /excludefs
      sort -u -o /tmp/onbuild/exclude.filelist /tmp/onbuild/exclude.filelist
   fi
   cd /
   if [ -n "$RUNDEPS" ] || [ -n "$RUNDEPS_UNTRUSTED" ]
   then
      apk --repositories-file /etc/apk/repositories --keys-dir /etc/apk/keys --no-cache --initramfs-diskless-boot --clean-protected --root /finalfs add --quiet --initdb
      set +x
      echo '++++++++++++++++++++++++++++++++++'
      echo '+++++++++ RUNDEPS <begin> ++++++++'
      echo '++++++++++++++++++++++++++++++++++'
      set -x
      if [ -n "$RUNDEPS" ]
      then
         apk --repositories-file /etc/apk/repositories --keys-dir /etc/apk/keys --no-cache --initramfs-diskless-boot --clean-protected --root /finalfs add $RUNDEPS
      fi
      if [ -n "$RUNDEPS_UNTRUSTED" ]
      then
         apk --repositories-file /etc/apk/repositories --keys-dir /etc/apk/keys --no-cache --initramfs-diskless-boot --clean-protected --root /finalfs --allow-untrusted add $RUNDEPS_UNTRUSTED
      fi
      set +x
      echo '----------------------------------'
      echo '---------- RUNDEPS </end> --------'
      echo '----------------------------------'
      set -x
   fi
fi
cd /finalfs
for dir in $MAKEDIRS
do
   dir="$(eval "echo $dir")"
   mkdir -p "${dir#/}"
done
for file in $MAKEFILES
do
   file="$(eval "echo $file")"
   file="${file#/}"
   mkdir -p "$(dirname "$file")"
   touch "$file"
done
find /tmp -path "/tmp/buildfs/*" -mindepth 2 -maxdepth 2 -exec cp -a "{}" / \;
find /tmp -path "/tmp/rootfs/*"  -mindepth 2 -maxdepth 2 -exec cp -a "{}" ./ \;
find /tmp -path "/tmp/finalfs/*"  -mindepth 2 -maxdepth 2 -exec cp -a "{}" ./ \;
chmod -R o= ./
n="0"
for contentimage in $CONTENTIMAGE1 $CONTENTIMAGE2 $CONTENTIMAGE3 $CONTENTIMAGE4
do
   n="$(expr $n + 1)"
   if [ "${contentimage#huggla}" == "$contentimage" ] && [ "$contentimage" != "scratch" ]
   then
      eval "contentdest=\"\$CONTENTDESTINATION$n\"" 
      find "$contentdest" -maxdepth 0 -exec chmod -R g-w,o= "{}" \;
      find "$contentdest" -type f -perm +010 -exec chmod g-x "{}" \;
   fi
done
find ./usr/local/bin -type f -exec chmod u=rx,go= "{}" \;
find / -path "/usr/local/bin/*" -type f -mindepth 3 -maxdepth 3 -exec chmod u=rx,go= "{}" \;
if [ -n "$INITCMDS" ]
then
   cd /
   set +x
   echo '++++++++++++++++++++++++++++++++++'
   echo '+++++++++ INITCMDS <begin> +++++++'
   echo '++++++++++++++++++++++++++++++++++'
   set -x
   eval "$INITCMDS"
   set +x
   echo '----------------------------------'
   echo '--------- INITCMDS </end> --------'
   echo '----------------------------------'
   set -x
fi
if [ -n "$BUILDCMDS" ]
then
   if [ -z "$DESTDIR" ]
   then
      if [ "${IMAGETYPE#*content}" != "$IMAGETYPE" ]
      then
         DESTDIR="content"
      fi
   fi
   cd /finalfs
   find . -mindepth 1 -type d -exec sh -c 'mkdir -p "$(echo "{}" | cut -c 2-)"' \;
   find . \( -type f -o -type l \) -exec sh -c 'cp -au "{}" "$(echo "{}" | cut -c 2-)"' \;
   mkdir -p "/root/.config" "$BUILDDIR" "/finalfs$DESTDIR"
   ln -sf /bin/bash /bin/sh
fi
if [ -n "$CLONEGITS" ]
then
   mkdir -p "$CLONEGITSDIR"
   cd "$CLONEGITSDIR"
   CLONEGITS="$(echo "$CLONEGITS" | sed "s/ '/,'/g" | sed "s/' /',/g")"
   IFS="$(echo -en ",")"
   set +x
   echo '++++++++++++++++++++++++++++++++++'
   echo '++++++++ CLONEGITS <begin> +++++++'
   echo '++++++++++++++++++++++++++++++++++'
   set -x
   for git in $CLONEGITS
   do
      eval "git clone $(eval "echo $git")"
   done
   set +x
   echo '----------------------------------'
   echo '-------- CLONEGITS </end> --------'
   echo '----------------------------------'
   set -x
   unset IFS
fi
if [ -n "$DOWNLOADS" ]
then
   mkdir -p "$DOWNLOADSDIR"
   cd "$DOWNLOADSDIR"
   set +x
   echo '++++++++++++++++++++++++++++++++++'
   echo '++++++++ DOWNLOADS <begin> +++++++'
   echo '++++++++++++++++++++++++++++++++++'
   set -x
   for download in $DOWNLOADS
   do
      wget "$download"
   done
   set +x
   echo '----------------------------------'
   echo '-------- DOWNLOADS </end> --------'
   echo '----------------------------------'
   set -x
   if [ "$DOWNLOADSDIR" == "$BUILDDIR" ]
   then
      find . -maxdepth 1 -type f \( -name "*.tar" -o -name "*.tar.*" \) -exec tar -xpf "{}" \;
      find . -maxdepth 1 -type f -name "*.zip" -exec unzip -o -d ./ "{}" \;
   fi
fi
if [ -n "$BUILDCMDS" ]
then
   if [ -n "${BUILDDEPS}" ] || [ -n "${BUILDDEPS_UNTRUSTED}" ]
   then
      set +x
      echo '++++++++++++++++++++++++++++++++++'
      echo '++++++++ BUILDDEPS <begin> +++++++'
      echo '++++++++++++++++++++++++++++++++++'
      set -x
      if [ -n "${BUILDDEPS}" ]
      then
         apk --no-cache --purge --force-overwrite --force-refresh --clean-protected --initramfs-diskless-boot add $BUILDDEPS
      fi
      if [ -n "${BUILDDEPS_UNTRUSTED}" ]
      then
         apk --no-cache --purge --force-overwrite --force-refresh --clean-protected --initramfs-diskless-boot allow-untrusted add $BUILDDEPS_UNTRUSTED
      fi
      set +x
      echo '----------------------------------'
      echo '-------- BUILDDEPS </end> --------'
      echo '----------------------------------'
      set -x
   fi
   tmpDESTDIR="$DESTDIR"
   DESTDIR="/finalfs$DESTDIR"
   cd "$BUILDDIR"
   set +x
   echo '++++++++++++++++++++++++++++++++++'
   echo '++++++++ BUILDCMDS <begin> +++++++'
   echo '++++++++++++++++++++++++++++++++++'
   set -x
   eval "$BUILDCMDS"
   set +x
   echo '----------------------------------'
   echo '-------- BUILDCMDS </end> --------'
   echo '----------------------------------'
   set -x
   DESTDIR="$tmpDESTDIR"
fi
cd /
rm -f /finalfs/etc/passwd /finalfs/etc/passwd- /finalfs/etc/group /finalfs/etc/group-
if [ -n "$FINALCMDS" ]
then
   set +x
   echo '++++++++++++++++++++++++++++++++++'
   echo '++++++++ FINALCMDS <begin> +++++++'
   echo '++++++++++++++++++++++++++++++++++'
   set -x
   chroot /finalfs /bin/sh -c "set -ex +fam && eval \"\$FINALCMDS\""
   set +x
   echo '----------------------------------'
   echo '-------- FINALCMDS </end> --------'
   echo '----------------------------------'
   set -x
fi
cd /finalfs
if [ -n "$EXECUTABLES" ] || [ -n "$STARTUPEXECUTABLES" ]
then
   if [ -n "$EXECUTABLES" ] && [ -n "$STARTUPEXECUTABLES" ]
   then
      EXECUTABLES="$EXECUTABLES $STARTUPEXECUTABLES"
   elif [ -z "$EXECUTABLES" ]
   then
      EXECUTABLES="$STARTUPEXECUTABLES"
   fi
   for exe in $EXECUTABLES
   do
      exe="${exe#/}"
      exeDir="$(dirname "$exe")"
      exeName="$(basename "$exe")"
      if [ "$exeDir" != "usr/local/bin" ]
      then
         relDir="$(relpath "/$exeDir" "/usr/local/bin")"
         cd "$exeDir"
         cp -a "./$exeName" "$relDir/"
         ln -sf "$relDir/$exeName" ./
         cd /finalfs
      fi
      if [ "$exeName" == "sudo" ]
      then
         chmod ug=rx,o= "usr/local/bin/$exeName"
      else
         chmod u=rx,go= "usr/local/bin/$exeName"
      fi
   done
fi
if [ -n "$EXPOSEFUNCTIONS" ]
then
   mkdir -p usr/local/bin/functions
   ln -s start/includeFunctions usr/local/bin/
   for func in $EXPOSEFUNCTIONS
   do
      ln -s start/functions/$func usr/local/bin/functions/
   done
fi
set -f
for exe in $STARTUPEXECUTABLES
do
   set +f
   echo "$exe" >> /environment/startupexecutables
done
if [ -s "/environment/startupexecutables" ]
then
   sort -u -o /environment/startupexecutables /environment/startupexecutables
fi
set -f
for file in $GID0WRITABLES
do
   set +f
   echo "$file" >> /environment/gid0writables
done
if [ -s "/environment/gid0writables" ]
then
   sort -u -o /environment/gid0writables /environment/gid0writables
fi
set -f
while read file
do
   set +f
   find ".$(dirname "$file")" -name "$(basename "$file")" -maxdepth 1 -exec chmod g+w "{}" \;
done </environment/gid0writables
set -f
for dir in $GID0WRITABLESRECURSIVE
do
   set +f
   echo "$dir" >> /environment/gid0writablesrecursive
done
if [ -s "/environment/gid0writablesrecursive" ]
then
   sort -u -o /environment/gid0writablesrecursive /environment/gid0writablesrecursive
fi
set -f
while read dir
do
   set +f
   find ".$(dirname "$dir")" -name "$(basename "$dir")" -maxdepth 1 -exec chmod -R g+w "{}" \;
done </environment/gid0writablesrecursive
set -f
for file in $LINUXUSEROWNED
do
   set +f
   echo "$file" >> /environment/linuxuserowned
done
if [ -s "/environment/linuxuserowned" ]
then
   sort -u -o /environment/linuxuserowned /environment/linuxuserowned
fi
set -f
for dir in $LINUXUSEROWNEDRECURSIVE
do
   set +f
   echo "$dir" >> /environment/linuxuserownedrecursive
done
if [ -s "/environment/linuxuserownedrecursive" ]
then
   sort -u -o /environment/linuxuserownedrecursive /environment/linuxuserownedrecursive
fi
set +f
find . -xdev \( -path "./var/cache/*" -o -path "./tmp/*" -o -path "./sys/*" -o -path "./proc/*" -o -path "./dev/*" -o -path "./lib/apk/*" -o -path "./etc/apk/*" \) \( -type f -o -type l \) -perm +0200 -delete
find . -depth -xdev \( -path "./var/cache/*" -o -path "./tmp/*" -o -path "./sys/*" -o -path "./proc/*" -o -path "./dev/*" -o -path "./lib/apk/*" -o -path "./etc/apk/*" \) -type d -perm +0200 -exec sh -c '[ -z "$(ls -A "{}")" ] && rm -r "{}"' \;
for dir in $REMOVEDIRS
do
   dir="$(eval "echo $dir")"
   dir="${dir#/finalfs}"
   dir="/finalfs$dir"
   if [ -d "$dir" ]
   then
      rm -rf "$dir"
   fi
done
for file in $REMOVEFILES
do
   file="$(eval "echo $file")"
   file="${file#/finalfs}"
   file="/finalfs$dir"
   if [ -f "$file" ] || [ -l "$file" ]
   then
      rm -f "$file"
   fi
done
if [ "$KEEPEMPTYDIRS" == "no" ]
then
   removeEmptyDirs "/finalfs"
fi
if [ -n "${DESTDIR#/}" ] && [ -n "$(ls -A "${DESTDIR#/}")" ] && ( [ "${IMAGETYPE#*content}" != "$IMAGETYPE" ] || [ "${IMAGETYPE#*base}" != "$IMAGETYPE" ] || [ "${IMAGETYPE#*application}" != "$IMAGETYPE" ] )
then
   DESTDIR="${DESTDIR#/}"
   (find . -type l -exec sh -c 'echo -n "$(echo "{}" | cut -c 2-)>"' \; -exec readlink "{}" \; && find . -type f -exec md5sum "{}" \; | awk '{first=$1; $1=""; print $0">"first}' | sed 's|^ [.]||') | sort -u - > /tmp/onbuild/exclude.filelist.new
   comm -12 /tmp/onbuild/exclude.filelist /tmp/onbuild/exclude.filelist.new | awk -F '>' '{system("rm -f \"."$1"\"")}'
   subdests="dev doc static"
   dev="${COMMON_CONFIGUREPREFIX#/}/lib/pkgconfig ${COMMON_CONFIGUREPREFIX#/}/include"
   doc="${COMMON_CONFIGUREPREFIX#/}/share/man ${COMMON_CONFIGUREPREFIX#/}/share/doc"
   if [ "${IMAGETYPE#*application}" != "$IMAGETYPE" ]
   then
      rm -rf "$DESTDIR-dev" "$DESTDIR-doc"
   fi
   if [ "${IMAGETYPE#*content}" != "$IMAGETYPE" ] || [ "${IMAGETYPE#*base}" != "$IMAGETYPE" ]
   then
      if [ -n "$RUNDEPS" ]
      then
         echo "$RUNDEPS" >> "$DESTDIR/RUNDEPS.txt"
      fi
      if [ "${IMAGETYPE#*content}" != "$IMAGETYPE" ]
      then
         cd "$DESTDIR"
         static="$(find ${COMMON_CONFIGUREPREFIX#/}/lib/*.a -maxdepth 0 \( -type f -o -type l \) | xargs)"
         cd /finalfs
         for subdest in $subdests
         do
            eval "files=\$$subdest"
            for file in $files
            do
               destfile="$DESTDIR/$file"
               if [ -e "$destfile" ]
               then
                  subdestdir="$DESTDIR-$subdest$(dirname "/$file")"
                  mkdir -p "$subdestdir"
                  cp -a "$destfile" "$subdestdir/"
                  rm -rf "$destfile"
               fi
            done
         done
         mkdir -p "$DESTDIR-app"
         cp -a $DESTDIR/* "$DESTDIR-app/"
         rm -rf "$DESTDIR"
      fi
   fi
fi
rm -f RUNDEPS.txt
(find . -type l -exec sh -c 'echo -n "$(echo "{}" | cut -c 2-)>"' \; -exec readlink "{}" \; && find . -type f -exec md5sum "{}" \; | awk '{first=$1; $1=""; print $0">"first}' | sed 's|^ [.]||') | sort -u - > /tmp/onbuild/exclude.filelist.new
comm -12 /tmp/onbuild/exclude.filelist /tmp/onbuild/exclude.filelist.new | awk -F '>' '{system("rm -f \"."$1"\"")}'
sort -u -o /tmp/onbuild/exclude.filelist /tmp/onbuild/exclude.filelist /tmp/onbuild/exclude.filelist.new
rm -f /tmp/onbuild/exclude.filelist.*
tar -c -z -f /environment/onbuild.tar.gz -C /tmp onbuild
mv /environment ./
if [ "${IMAGETYPE#*content}" != "$IMAGETYPE" ]
then
   for siblingdir in $DESTDIR*
   do
      cp -a $siblingdir/* ./
      sibling="${siblingdir#$DESTDIR}"
      sibling="${sibling#-}"
      contentfile="${IMAGEID}${sibling:+-$sibling}"
      cd "$siblingdir"
      find . -mindepth 1 ! -name "$contentfile" | cut -c 2- > "$contentfile"
      gzip "$contentfile"
      cd ..
   done
fi
set +e
chmod 755 ./ ./lib ./usr ./usr/lib ./usr/local ./usr/local/bin
chmod 700 ./bin ./sbin ./usr/bin ./usr/sbin
chmod 750 ./etc ./var ./run ./var/cache ./start ./stop
setfacl --restore=/tmp/init-permissions.txt
exit 0
