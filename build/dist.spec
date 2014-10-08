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

BuildRoot: %{_tmppath}/%{name}-%{version}-BUILD

%description
<% $zilla->abstract %>

%prep
%setup -q -n <% $zilla->name %>-%{version}

%build
perl Makefile.PL
make test

%install
if [ "%{buildroot}" != "/" ] ; then
rm -rf %{buildroot}
fi
make install DESTDIR=%{buildroot}
%{__mkdir_p} %{buildroot}/var/lib/zxtm/rrds
%{__mkdir_p} %{buildroot}/var/lib/zxtm/graphs
%{__mkdir_p} %{buildroot}/etc
cp zxtm-dist.conf %{buildroot}/etc/zxtm.conf

find %{buildroot} | sed -e 's#%{buildroot}##' > %{_tmppath}/filelist

%clean
if [ "%{buildroot}" != "/" ] ; then
rm -rf %{buildroot}
fi

%files -f %{_tmppath}/filelist
%defattr(-,root,root)
%attr(600, root, root) /etc/zxtm.conf
%config /etc/zxtm.conf
