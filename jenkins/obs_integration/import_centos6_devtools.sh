#! /bin/bash
# This script wraps the devtoolset-4 repository for CentOS-6 as an RPM-package.
# The eclipes packages are excluded for now.
#
# rpm -qa | grep devtoolset-4 | grep -v eclipse | wc -l
#  81
# cat /etc/yum.repos.d/CentOS-SCLo-scl-rh.repo
#
# Used with e.g.
# isv:ownCloud:devel:Qt562/devtoolset-4-centos-6-x86-64

version=0.2

pkgname=devtoolset-4-centos6-x86-64
upstream_repo=http://mirror.centos.org/centos/6/sclo/x86_64/rh/devtoolset-4/
cutdirs=5	# leave only devtoolset-4 as a directory.

pkgvers=0.1_oc$(date +"%Y%m%d")

# tmpdir=/tmp/dt-$$/
tmpdir=/tmp/dt-12567

mkdir -p $tmpdir
# ( cd $tmpdir; wget -r -nH --cut-dirs=$cutdirs -np $upstream_repo )
find $tmpdir -name index.html\*    | xargs rm -f
find $tmpdir -name \*-eclipse-\*   | xargs rm -f

rm -rf scripts; mkdir -p scripts
:> dependencies
## Must loop aphabetically sorted, so that newest version number comes last.
## We weed out older versions by using uniquename.
for pkg in $tmpdir/*/*.rpm; do
  rpm -qp --nosignature --requires $pkg  | sed -e 's@^@Requires: @'  >> dependencies
  rpm -qp --nosignature --provides $pkg  | sed -e 's@^@Provides: @'  >> dependencies
  rpm -qp --nosignature --obsoletes $pkg | sed -e 's@^@Obsoletes: @' >> dependencies
  rpm -qp --nosignature --conflicts $pkg | sed -e 's@^@Conflicts: @' >> dependencies
  uniquename=$(echo $pkg | sed -e 's@-[0-9][^-]*-[0-9][^-]*.\(x86_64\|i586\|noarch\).rpm$@.\1.rpm@')
  test "$pkg" != "$uniquename" && mv $pkg $uniquename
  base=$(basename $uniquename .rpm)
  out=scripts/$base.none
  rpm -qp --nosignature --scripts $uniquename | while read -r line; do
    case "$line" in

      "postinstall scriptlet (using /bin/sh):")
        out=scripts/$base.postinstall
        ;;

      "postuninstall scriptlet (using /bin/sh):")
        out=scripts/$base.postuninstall
        ;;

      "preinstall scriptlet (using /bin/sh):")
        out=scripts/$base.preinstall
        ;;

      "preuninstall scriptlet (using /bin/sh):")
        out=scripts/$base.preuninstall
        ;;

      "postinstall program: "*)
        out=scripts/$base.postinstall
        echo $line | sed -e 's@^postinstall program: @@' >> $out
        out=scripts/$base.none
        ;;

      "postuninstall program: "*)
        out=scripts/$base.postuninstall
        echo $line | sed -e 's@^postuninstall program: @@' >> $out
        out=scripts/$base.none
        ;;

      *)
        echo $line >> $out
        ;;
    esac
  done
done

cat <<EOF_SPEC1 > $pkgname.spec
# ATTENTION: DO NOT EDIT. this file is generated by $0.
# ATTENTION: It will be overwritten by the next run. 
Name:           $pkgname
Version:        $pkgvers
Release:        1
License:        GPL
BuildRoot:      %{_tmppath}/%{name}-%{version}-build
Group:          Development
Summary:        CentOS-6 devtoolset as a package.
Source:         $pkgname.tar.bz2
Source1:        $pkgname-scripts.tar.bz2
# rpm provides /usr/bin/rpm2cpio
BuildRequires:  rpm cpio	
AutoReqProv:    no

# Disable /usr/lib/rpm/find-debuginfo.sh
# It crashes with Failed to write file: invalid section entry size
%define debug_package %{nil}

%description
Tar ball created with 
$0 VERSION $version using
upstream_repo=$upstream_repo

EOF_SPEC1
sort -u dependencies >> $pkgname.spec
cat <<EOF_SPEC2 >> $pkgname.spec

%prep
%setup -T -c

%build
tar xvf %{S:0}

%install
set +x
for pkg in */*.rpm; do
  rpm -qp --nosignature \$pkg
  rpm2cpio \$pkg | (cd %{buildroot} && cpio -idmu)
done
set -x
# extra hacks: I need my files readable and my dirs writable
# to avoid
# create archive failed on file .../opt/rh/devtoolset-4/root/usr/bin/staprun: cpio: Bad magic
# rm: cannot remove .../opt/rh/devtoolset-4/root/usr/lib64/perl5/vendor_perl/Authen: Permission denied
chmod -R u+r %{buildroot}/*
find %{buildroot} -type d -print0 | xargs -0 chmod u+w

mkdir -p %{buildroot}/usr/share/%{name}
tar xvf %{S:1} -C %{buildroot}/usr/share/%{name}
ls -la %{buildroot}/usr/share/%{name}/*

%clean
rm -rf "%{buildroot}"

%files
%defattr(-,root,root)
/opt/*
/usr/*
/etc/*

%pre
for s in /usr/share/%{name}/scripts/*.preinstall; do
  sh \$s \$1
done

%preun
for s in /usr/share/%{name}/scripts/*.preuninstall; do
  sh \$s \$1
done

%post
for s in /usr/share/%{name}/scripts/*.postinstall; do
  sh \$s \$1
done

%postun
for s in /usr/share/%{name}/scripts/*.postuninstall; do
  sh \$s \$1
done

%changelog
EOF_SPEC2


tar jcvf $pkgname-scripts.tar.bz2 scripts
# tar jcvf $pkgname.tar.bz2 -C $tmpdir .
# rm -rf $tmpdir

osc add $pkgname.tar.bz2 
osc add $pkgname-scripts.tar.bz2
osc add $pkgname.spec 

