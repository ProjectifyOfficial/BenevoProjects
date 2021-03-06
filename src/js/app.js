App = {
  web3Provider: null,
  contracts: {},

  // Load up example projects
  init: function() {
    $.getJSON('../projects.json', function(data) {
      var projectRow = $('#projectRow');
      var projectTemplate = $('#projectTemplate');

      // Bootstrap the Contract abstraction for use with the current web3 instance
      // OraclizeContract.setProvider(web3.currentProvider);
      for (i = 0; i < data.length; i ++) {
        projectTemplate.find('.panel-title').text(data[i].name);
        projectTemplate.find('img').attr('src', data[i].picture);
        projectTemplate.find('.goal-amount').text(data[i].goalAmount);
        projectTemplate.find('.current-amount').text(data[i].currentAmount);
        projectRow.append(projectTemplate.html());
      }
    });
    return App.initWeb3();
  },

  initWeb3: function() {
    if (typeof web3 !== 'undefined') {
      App.web3Provider = web3.currentProvider;
      web3 = new Web3(web3.currentProvider);
    } else {
      // If no injected web3 instance is detected, fall back to ganache-cli
      App.web3Provider = new Web3.providers.HttpProvider('http://localhost:8545');
      web3 = new Web3(App.web3Provider);
    }
    return App.initContract();
  },

  initContract: function() {
    $.getJSON('BenevoProjects.json', function(projects){
      App.contracts.BenevoProjects = TruffleContract(projects);
      App.contracts.BenevoProjects.setProvider(App.web3Provider);
      // return App.markDonated();
      App.listenForEvents();
      return App.render();
      // return App.bindEvents();
    });
  },

  // Listen for events emitted from the contracts
  listenForEvents: function() {
    App.contracts.BenevoProjects.deployed().then(function(instance) {
      // Restart Chrome if unable to receive this event
      instance.Donated({}, {
        fromBlock: 0,
        toBlock: 'latest'
      }).watch(function(error, event) {
        console.log("event triggered", event)
        // Reload when Donated
        App.render();
      });
      instance.NewProject({}, {
        fromBlock: 0,
        toBlock: 'latest'
      }).watch(function(error, event) {
        console.log("event triggered", event)
        // Reload when Donated
        App.render();
      });
      instance.Withdraw({}, {
        fromBlock: 0,
        toBlock: 'latest'
      }).watch(function(error, event) {
        console.log("event triggered", event)
        // Reload when Donated
        App.render();
      });
    });
  },

  render: function() {

  }

  // Opens a socket and listens for Events defined in Oracle.sol
  addEventListeners: function(instance){
    var LogCreated = instance.LogUpdate({},{fromBlock: 0, toBlock: 'latest'});
    var LogPollutionUpdated = instance.LogPollutionUpdated({},{fromBlock: 0, toBlock: 'latest'});
    var LogInfo = instance.LogInfo({},{fromBlock: 0, toBlock: 'latest'});

    LogPollutionUpdate.watch(function(err, result){
      if(!err){
        App.pollution = result;
        App.showPollution(App.pollution, App.currentBalance);
      }else{
        console.log(err)
      }
    })

    // Emitted when the Oracle.sol's constructor is run
    LogCreated.watch(function(err, result){
      if(!err){
        console.log('Contract created!');
        console.log('Owner: ' , result.args._owner);
        console.log('Balance: ' , web3.fromWei(result.args._balance, 'ether').toString(), 'ETH');
        console.log('-----------------------------------');
      }else{
        console.log(err)
      }
    })

    // Emitted when a text message needs to be logged to the front-end from the Contract
    LogInfo.watch(function(err, result){
      if(!err){
        console.info(result.args)
      }else{
        console.error(err)
      }
    })
  },

  showPollution: function(pollution){
    var row = document.getElementById('row');

    var pollution_element = document.getElementById("pollution");
    pollution_element.innerHTML = pollution;
  },


  bindEvents: function() {
    $(document).on('click', '.btn-donate', App.Donate);
  },

  markDonated: function(donors, account) {
    var donationInstance;
    
    App.contracts.BenevoProjects.deployed().then(function(instance){
      donationInstance = instance;

      return donationInstance.getDonors.call();
    }).then(function(donors){
      for (i=0; i < donors.length; i++){
        if (donors[i] !== '0x0000000000000000000000000000000000000000') {
          $('.panel-project').eq(i).find('button').text('Success').attr('disabled', true);
        }
      }
    }).catch(function(err) {
      console.log(err.message);
    });
  },

  Donate: function(event) {
    event.preventDefault();

    var projectId = parseInt($(event.target).data('id'));
    var donationInstance;

    web3.eth.getAccounts(function(error, accounts){
      if (error) {
        console.log(error);
      }

      var account = accounts[0];

      App.contracts.BenevoProjects.deployed().then(function(instance){
        donationInstance = instance;
        return donationInstance.donate(projectId, {from: account});
      }).then(function(result){
        return App.markDonated();
      }).catch(function(err) {
        console.log(err.message);
      });
    });
  }
};

$(function() {
  $(window).load(function() {
    App.init();
  });
});
