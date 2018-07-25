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
Source6 : proxysql-logrotate
Source7 : proxysql-status
URL: http://www.proxysql.com/
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root
Requires: logrotate
Requires(pre): shadow-utils

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
install -d  %{buildroot}/%{_sysconfdir}/logrotate.d
install -m 0755 src/proxysql %{buildroot}/%{_bindir}
install -m 0640 etc/proxysql.cnf %{buildroot}/%{_sysconfdir}
install -m 0640 %SOURCE2 %{buildroot}/%{_sysconfdir}
sed -i 's|proxysql \$OPTS|if [[ $(whoami) = "proxysql" ]]; then \n proxysql $OPTS\n else \n su proxysql -s /bin/sh -c "/usr/bin/proxysql $OPTS" \n fi|' etc/init.d/proxysql
install -m 0755 etc/init.d/proxysql %{buildroot}/%{_sysconfdir}/init.d
install -d %{buildroot}/var/lib/proxysql
install -d %{buildroot}/var/run/proxysql
install -m 0775 %SOURCE1 %{buildroot}/%{_bindir}/proxysql-admin
install -m 0775 %SOURCE3 %{buildroot}/%{_bindir}/proxysql_galera_checker
install -m 0775 %SOURCE4 %{buildroot}/%{_bindir}/proxysql_node_monitor
install -m 0775 %SOURCE7 %{buildroot}/%{_bindir}/proxysql-status
install -m 0644 %SOURCE6 %{buildroot}%{_sysconfdir}/logrotate.d/proxysql-logrotate

%clean
rm -rf %{buildroot}


%pre
getent group proxysql >/dev/null || groupadd -r proxysql
useradd -r -g proxysql -r -d /var/lib/proxysql -s /bin/false \
    -c "ProxySQL" proxysql >/dev/null 2>&1 || :

STATUS_FILE=/tmp/PROXYSQL_UPGRADE_MARKER
EXIST=$(ps wwaux | grep /usr/bin/proxysql | grep -v grep | wc -l )
if [ "$EXIST" -gt "0" ]; then
    echo "SERVER_TO_START=1" >> $STATUS_FILE
else
    echo "SERVER_TO_START=0" >> $STATUS_FILE
fi



%post
case "$1" in
    1)
        chkconfig --add %{name}
    ;;
    2)
        STATUS_FILE=/tmp/PROXYSQL_UPGRADE_MARKER
        if [ -f $STATUS_FILE ] ; then
            SERVER_TO_START=`grep '^SERVER_TO_START=' $STATUS_FILE | cut -c17-`
            rm -f $STATUS_FILE
        else
            SERVER_TO_START=''
        fi
        if [ "x$SERVER_TO_START" = "x1" ]; then
            %{_sysconfdir}/init.d/proxysql stop
            %{_sysconfdir}/init.d/proxysql start
        fi
        chkconfig --add %{name}
    ;;
esac
exit 0

%preun
    echo "HERE $1" > /tmp/test
if [ "$1" = "0" ]; then
    /sbin/service proxysql stop >/dev/null 2>&1 || :
    /sbin/chkconfig --del %{name}
fi
exit 0

%postun
if [ "$1" = "0" ]; then
    rm -rf /var/run/%{name}
fi
exit 0

%files
%defattr(-,root,root,-)
%{_bindir}/proxysql_galera_checker
%{_bindir}/proxysql-admin
%{_bindir}/proxysql-status
%{_bindir}/proxysql_node_monitor
%{_sysconfdir}/logrotate.d/proxysql-logrotate
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
* Tue Aug 09 2017  Evgeniy Patlan <evgeniy.patlan@percona.com> 1.3.9-1.1
- added proxysql-logrotate

* Wed Sep 21 2016  Evgeniy Patlan <evgeniy.patlan@percona.com> 1.2.3-1.0.1
- added proxysql-admin tool

* Fri Jul 15 2016  Evgeniy Patlan <evgeniy.patlan@percona.com> 1.2.0-1.0.1
- First build of proxysql for Percona.
