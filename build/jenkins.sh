#!/bin/sh

set -x

perlbrew init
source ~/perl5/perlbrew/etc/bashrc
perlbrew install-cpanm
cpanm --local-lib=~/perl5 local::lib && eval $(perl -I ~/perl5/lib/perl5/ -Mlocal::lib)
cpanm Dist::Zilla

dzil authordeps --missing | cpanm
cpanm Test::Perl::Critic Archive::Tar::Wrapper

dzil clean
dzil test
dzil mkrpmspec
dzil build

perlbrew off
eval $(perl -I ~/perl5/lib/perl5/ -Mlocal::lib=--deactivate)

build/rpmbuild *.tar.gz
echo "rpmbuild rc=$?"

mkdir -p rpms/SRPMS
mkdir -p rpms/RPMS/noarch

mv $HOME/rpmbuild/SRPMS/$JOB_NAME* rpms/SRPMS/
mv $HOME/rpmbuild/RPMS/noarch/$JOB_NAME* rpms/RPMS/noarch/

gpg --export -a jenkins@mozilla.org > rpms/RPM-KEY

cat << EOF > rpms/$JOB_NAME.repo
[$JOB_NAME]
name=$JOB_NAME
baseurl=${JOB_URL}lastSuccessfulBuild/artifact/rpms/
gpgcheck=1
gpgkey=${JOB_URL}lastSuccessfulBuild/artifact/rpms/RPM-KEY
enabled=1
EOF

createrepo -v --revision=$BUILD_NUMBER --update rpms
