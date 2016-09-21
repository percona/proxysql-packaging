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
URL: http://www.proxysql.com/

BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root

%description
%{summary}

%prep
%setup -q

%build
sed -i -e 's/c++11/c++0x/' lib/Makefile
sed -i -e 's/c++11/c++0x/' src/Makefile
make clean
make -j 4 build_deps
make -j 4

%install
install -d %{buildroot}/%{_bindir}
install -d  %{buildroot}/%{_sysconfdir}
install -d  %{buildroot}/%{_sysconfdir}/init.d
install -m 0755 src/proxysql %{buildroot}/%{_bindir}
install -m 0640 etc/proxysql.cnf %{buildroot}/%{_sysconfdir}
install -m 0755 etc/init.d/proxysql %{buildroot}/%{_sysconfdir}/init.d
install -d %{buildroot}/var/lib/proxysql
install -d %{buildroot}/var/run/proxysql
install -m 0750  %{_builddir}/%{name}-%{version}/tools/proxysql_galera_checker.sh %{buildroot}/%{_bindir}/proxysql_galera_checker
install -m 0750 %SOURCE1 %{buildroot}/%{_bindir}/proxysql-admin


%clean
rm -rf %{buildroot}


%pre
/usr/sbin/groupadd -g 28 -o -r proxysql >/dev/null 2>&1 || :
/usr/sbin/useradd  -g proxysql -o -r -d /var/lib/proxysql -s /bin/false \
    -c "ProxySQL" -u 28 proxysql >/dev/null 2>&1 || :


%post
mkdir /var/run/%{name}
chkconfig --add %{name}


%preun
/sbin/service proxysql stop >/dev/null 2>&1 || :
/sbin/chkconfig --del proxysql

%postun
rm -rf /var/run/%{name}
chkconfig --del %{name}

%files
%defattr(-,root,root,-)
%config(noreplace) %{_sysconfdir}/%{name}.cnf
%defattr(-,proxysql,proxysql,-)
%{_bindir}/proxysql
%{_bindir}/proxysql-admin
%{_sysconfdir}/init.d/%{name}
/var/lib/proxysql
/var/run/proxysql
%defattr(-,root,proxysql,-)
%{_bindir}/proxysql_galera_checker


%changelog
* Wed Sep 21 2016  Evgeniy Patlan <evgeniy.patlan@percona.com> 1.2.3-1.0.1
- added proxysql-admin tool

* Fri Jul 15 2016  Evgeniy Patlan <evgeniy.patlan@percona.com> 1.2.0-1.0.1
- First build of proxysql for Percona.
