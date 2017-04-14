# Don't try fancy stuff like debuginfo, which is useless on binary-only
# packages. Don't strip binary too
# Be sure buildpolicy set to do nothing
%define        __spec_install_post %{nil}
%define          debug_package %{nil}
%define        __os_install_post %{_dbpath}/brp-compress

Summary: A high-performance MySQL proxy
Name: proxysql
Version: @@VERSION@@
Release: @@RELEASE@@
License: GPL+
Group: Development/Tools
Source0 : %{name}-%{version}.tar.gz
Source1 : proxysql-admin
Source2 : proxysql-admin.cnf
Source3 : proxysql_galera_checker
Source4 : proxysql_node_monitor
Source5 : LICENSE
URL: http://www.proxysql.com/
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root

%description
%{summary}

%prep
%setup -q
install %SOURCE5 %{name}-%{version}

%build
sed -i -e 's/c++11/c++0x/' lib/Makefile
sed -i -e 's/c++11/c++0x/' src/Makefile
make clean
make

%install
install -d %{buildroot}/%{_bindir}
install -d  %{buildroot}/%{_sysconfdir}
install -d  %{buildroot}/%{_sysconfdir}/init.d
install -m 0755 src/proxysql %{buildroot}/%{_bindir}
install -m 0640 etc/proxysql.cnf %{buildroot}/%{_sysconfdir}
install -m 0640 %SOURCE2 %{buildroot}/%{_sysconfdir}
install -m 0755 etc/init.d/proxysql %{buildroot}/%{_sysconfdir}/init.d
install -d %{buildroot}/var/lib/proxysql
install -d %{buildroot}/var/run/proxysql
install -m 0775 %SOURCE1 %{buildroot}/%{_bindir}/proxysql-admin
install -m 0775 %SOURCE3 %{buildroot}/%{_bindir}/proxysql_galera_checker
install -m 0775 %SOURCE4 %{buildroot}/%{_bindir}/proxysql_node_monitor


%clean
rm -rf %{buildroot}


%pre
/usr/sbin/groupadd -g 28 -o -r proxysql >/dev/null 2>&1 || :
/usr/sbin/useradd  -g proxysql -o -r -d /var/lib/proxysql -s /bin/false \
    -c "ProxySQL" -u 28 proxysql >/dev/null 2>&1 || :


%post
chkconfig --add %{name}


%preun
/sbin/service proxysql stop >/dev/null 2>&1 || :
/sbin/chkconfig --del proxysql

%postun
rm -rf /var/run/%{name}

%files
%defattr(-,root,root,-)
%{_bindir}/proxysql_galera_checker
%{_bindir}/proxysql-admin
%{_bindir}/proxysql_node_monitor
%defattr(-,proxysql,proxysql,-)
%{_bindir}/proxysql
%{_sysconfdir}/init.d/%{name}
/var/lib/proxysql
/var/run/proxysql
%defattr(-,root,proxysql,-)
%config(noreplace) %{_sysconfdir}/%{name}.cnf
%config(noreplace) %{_sysconfdir}/proxysql-admin.cnf
%doc LICENSE

%changelog
* Wed Sep 21 2016  Evgeniy Patlan <evgeniy.patlan@percona.com> 1.2.3-1.0.1
- added proxysql-admin tool

* Fri Jul 15 2016  Evgeniy Patlan <evgeniy.patlan@percona.com> 1.2.0-1.0.1
- First build of proxysql for Percona.
