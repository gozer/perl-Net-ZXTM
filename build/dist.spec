Name: perl-<% $zilla->name %>
Version: <% (my $v = $zilla->version) =~ s/^v//; $v %>
Release: 1.<% $ENV{BUILD_NUMBER} || 1 %>

Summary: <% $zilla->abstract %>
License: GPL+ or Artistic
Group: Applications/CPAN
BuildArch: noarch
URL: <% $zilla->license->url %>
Vendor: <% $zilla->license->holder %>
Source: <% $archive %>
Requires: crontabs

BuildRoot: %{_tmppath}/%{name}-%{version}-BUILD

%description
<% $zilla->abstract %>

%prep
%setup -q -n <% $zilla->name %>-%{version}

%build
perl Makefile.PL INSTALLDIRS=vendor
make test

%install
if [ "%{buildroot}" != "/" ] ; then
rm -rf %{buildroot}
fi

make pure_install DESTDIR=%{buildroot}

find $RPM_BUILD_ROOT -type f -name .packlist -exec rm -f {} \;

%{_fixperms} $RPM_BUILD_ROOT/*

%{__mkdir_p} %{buildroot}%{_sharedstatedir}/zxtm/rrds
%{__mkdir_p} %{buildroot}%{_sharedstatedir}/zxtm/rrds/global
%{__mkdir_p} %{buildroot}%{_localstatedir}/www/html/zxtm/graphs
%{__mkdir_p} %{buildroot}%{_localstatedir}/www/html/zxtm
%{__mkdir_p} %{buildroot}%{_datarootdir}/zxtm/templates
%{__mkdir_p} %{buildroot}%{_sysconfdir}
%{__mkdir_p} %{buildroot}%{_initddir}
%{__mkdir_p} %{buildroot}%{_sysconfdir}/cron.d
%{__mkdir_p} %{buildroot}%{_localstatedir}/log/zxtm

cp zxtm-dist.conf %{buildroot}%{_sysconfdir}/zxtm.conf
cp tt/* %{buildroot}%{_datarootdir}/zxtm/templates
cp cron.d/* %{buildroot}%{_sysconfdir}/cron.d
ln -s %{_bindir}/zxtm-rrd %{buildroot}%{_initddir}/zxtm-rrd

%clean
if [ "%{buildroot}" != "/" ] ; then
rm -rf %{buildroot}
fi

%files
%defattr(-,root,root)
%doc README README.md CHANGES LICENSE
%config(noreplace)  %attr(0700,root,root) %{_sysconfdir}/zxtm.conf
%{perl_vendorlib}/*
%{_mandir}/man?/*
%{_datarootdir}/zxtm/templates
%{_initddir}/zxtm-rrd
%{_bindir}/zxtm-*
%config(noreplace) %{_sysconfdir}/zxtm.conf
%{_sysconfdir}/cron.d/zxtm
%attr(0775,nobody,root) %{_sharedstatedir}/zxtm/rrds
%attr(0775,nobody,root) %{_sharedstatedir}/zxtm/rrds/global
%{_localstatedir}/www/html/zxtm
%{_localstatedir}/www/html/zxtm/graphs
%changelog
