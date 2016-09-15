var servers = {};


function Addon(addonName, addonVersion) {
    self.name = name;
    self.version = version;
}
Addon.prototype.getName = function getName() {
    return self.name;
};
Addon.prototype.getVersion = function getVersion() {
    return self.version;
};

function Server(ipAddress) {
    self.ipAddress = ipAddress;
    self.hostname = 'unknown name';
    self.addons = [];
    self.accessTime = (new Date()).getTime();
}
Server.prototype.addAddon = function addAddon(newAddon) {
    self.addons = self.addons.filter(function(addon) {
        return addon.name !== newAddon.name;
    });
    self.addons.push(new Addon(newAddon))
};


module.exports.getServer = function(serverIp) {
    if (servers[serverIp] !== undefined) {
        servers[serverIp].accessTime = (new Date()).getTime();
        return servers[serverIp];
    }
    servers[serverIp] = new Server(serverIp);
};

module.exports.getAddon = function(servers) {

};