#########################################
# Testing scripts for MNIST experiments #
#########################################

import numpy as np
import theano
import theano.tensor as T
import theano.tensor.shared_randomstreams

from FrankeNet import SS_DEV_NET
from load_data import load_udm, load_udm_ss
import NetTrainers as NT

def train_ss_mlp(NET, mlp_params, sgd_params, rng, su_count=1000):
    """Run semisupervised DEV-regularized test."""

    # Load some data to train/validate/test with
    dataset = 'data/mnist.pkl.gz'
    datasets = load_udm_ss(dataset, su_count, rng)

    # Tell the net that it's semisupervised, which will force it to use only
    # unlabeled examples for computing the DEV regularizer.
    NET.is_semisupervised = 1

    # Run training on the given NET
    NT.train_ss_mlp(NET=NET, \
        mlp_params=mlp_params, \
        sgd_params=sgd_params, \
        datasets=datasets)
    return 1

def train_mlp(NET, mlp_params, sgd_params):
    """Run mlp training test."""

    # Load some data to train/validate/test with
    dataset = 'data/mnist.pkl.gz'
    datasets = load_udm(dataset)

    # Tell the net that it's not semisupervised, which will force it to use
    # _all_ examples for computing the DEV regularizer.
    NET.is_semisupervised = 0

    # Train the net
    NT.train_mlp(NET=NET, \
        mlp_params=mlp_params, \
        sgd_params=sgd_params, \
        datasets=datasets)
    return 1

def train_dae(NET, dae_layer, mlp_params, sgd_params):
    """Run DAE training test."""

    # Load some data to train/validate/test with
    dataset = 'data/mnist.pkl.gz'
    datasets = load_udm(dataset)

    # Run denoising autoencoder training on the given layer of NET
    NT.train_dae(NET=NET, \
        dae_layer=dae_layer, \
        mlp_params=mlp_params, \
        sgd_params=sgd_params, \
        datasets=datasets)
    return 1

def test_dae(dae_layer=0, mlp_params=False, sgd_params=False):
    """Setup basic test for semisupervised DEV-regularized MLP."""

    if not sgd_params:
        # Set some reasonable sgd parameters
        sgd_params = {}
        sgd_params['start_rate'] = 0.002
        sgd_params['decay_rate'] = 0.998
        sgd_params['wt_norm_bound'] = 3.5
        sgd_params['epochs'] = 1000
        sgd_params['batch_size'] = 50
        sgd_params['mlp_type'] = 'dev'
        sgd_params['result_tag'] = 'xxx'
    if not mlp_params:
        # Set some reasonable mlp parameters
        mlp_params = {}
        mlp_params['layer_sizes'] = [28*28, 500, 500, 11]
        mlp_params['dev_clones'] = 1
        mlp_params['dev_types'] = [1, 1, 2]
        mlp_params['dev_lams'] = [0.1, 0.1, 2.0]
        mlp_params['dev_mix_rate'] = 0.5
        mlp_params['lam_l2a'] = 1e-3
        mlp_params['use_bias'] = 1

    # Initialize a random number generator for this test
    rng = np.random.RandomState(12345)

    # Construct the SS_DEV_NET object that we will be training
    x_in = T.matrix('x_in')
    NET = SS_DEV_NET(rng=rng, input=x_in, params=mlp_params)

    # Initialize biases in each net layer (except final layer) to zero
    for layer in NET.mlp_layers:
        b_init = layer.b.get_value(borrow=False)
        b_const = np.zeros(b_init.shape, dtype=theano.config.floatX)
        layer.b.set_value(b_const)

    # Run semisupervised training on the given MLP
    train_dae(NET, dae_layer, mlp_params, sgd_params)
    return 1

def test_ss_mlp(sgd_params=False, mlp_params=False, su_count=1000, rng_seed=1234):
    """Setup basic test for semisupervised DEV-regularized MLP."""

    if not sgd_params:
        # Set some reasonable sgd parameters
        sgd_params = {}
        sgd_params['start_rate'] = 0.1
        sgd_params['decay_rate'] = 0.998
        sgd_params['wt_norm_bound'] = 3.5
        sgd_params['epochs'] = 1000
        sgd_params['batch_size'] = 128
        sgd_params['mlp_type'] = 'dev'
        sgd_params['result_tag'] = 'xxx'
    if not mlp_params:
        # Set some reasonable mlp parameters
        mlp_params = {}
        mlp_params['layer_sizes'] = [28*28, 500, 500, 11]
        mlp_params['dev_clones'] = 1
        mlp_params['dev_types'] = [1, 1, 2]
        mlp_params['dev_lams'] = [0.1, 0.1, 2.0]
        mlp_params['dev_mix_rate'] = 0.5
        mlp_params['lam_l2a'] = 1e-3
        mlp_params['use_bias'] = 1

    # Initialize a random number generator for this test
    rng = np.random.RandomState(rng_seed)

    # Construct the SS_DEV_NET object that we will be training
    x_in = T.matrix('x_in')
    NET = SS_DEV_NET(rng=rng, input=x_in, params=mlp_params)

    # Initialize biases in each net layer (except final layer) to small
    # positive constants (rather than their default zero initialization)
    for (num, layer) in enumerate(NET.mlp_layers):
        b_init = layer.b.get_value(borrow=False)
        b_const = np.zeros(b_init.shape, dtype=theano.config.floatX)
        if (num < (len(NET.mlp_layers)-1)):
            b_const = b_const + 0.1
        layer.b.set_value(b_const)

    # Run semisupervised training on the given MLP
    train_ss_mlp(NET, mlp_params, sgd_params, rng, su_count)
    return 1

def batch_test_ss_mlp(test_count=10, su_count=1000):
    """Run multiple semisupervised learning tests."""

    # Set some reasonable sgd parameters
    sgd_params = {}
    sgd_params['start_rate'] = 0.1
    sgd_params['decay_rate'] = 0.998
    sgd_params['wt_norm_bound'] = 3.5
    sgd_params['epochs'] = 1000
    sgd_params['batch_size'] = 128
    sgd_params['mlp_type'] = 'dev'
    # Set some reasonable mlp parameters
    mlp_params = {}
    mlp_params['layer_sizes'] = [28*28, 500, 500, 11]
    mlp_params['dev_clones'] = 1
    mlp_params['dev_types'] = [1, 1, 2]
    mlp_params['dev_lams'] = [0.1, 0.1, 2.0]
    mlp_params['dev_mix_rate'] = 0.5
    mlp_params['lam_l2a'] = 1e-3
    mlp_params['use_bias'] = 1

    # Run tests with different sorts of regularization
    for test_num in range(test_count):
        # Run test with no droppish regularization
        sgd_params['result_tag'] = "ss_raw_500x500_{0:d}".format(test_num)
        sgd_params['mlp_type'] = 'raw'
        mlp_params['dev_lams'] = [0., 0., 0.]
        test_ss_mlp(mlp_params=mlp_params, sgd_params=sgd_params, \
                su_count=su_count, rng_seed=test_num)
        # Run test with standard dropout on supervised examples
        sgd_params['result_tag'] = "ss_sde_500x500_{0:d}".format(test_num)
        sgd_params['mlp_type'] = 'sde'
        test_ss_mlp(mlp_params=mlp_params, sgd_params=sgd_params, \
                su_count=su_count, rng_seed=test_num)
        # Run test with DEV regularization on unsupervised examples
        sgd_params['result_tag'] = "ss_dev_500x500_{0:d}".format(test_num)
        sgd_params['mlp_type'] = 'dev'
        mlp_params['dev_lams'] = [0.1, 0.1, 2.0]
        test_ss_mlp(mlp_params=mlp_params, sgd_params=sgd_params, \
                su_count=su_count, rng_seed=test_num)
    return 1

def test_ss_mlp_pt(mlp_params=False, sgd_params=False, su_count=1000):
    """Setup basic test for semisupervised DEV-regularized MLP."""

    if not sgd_params:
        # Set some reasonable sgd parameters
        sgd_params = {}
        sgd_params['start_rate'] = 0.1
        sgd_params['decay_rate'] = 0.998
        sgd_params['wt_norm_bound'] = 3.5
        sgd_params['epochs'] = 1000
        sgd_params['batch_size'] = 128
        sgd_params['mlp_type'] = 'dev'
        sgd_params['result_tag'] = 'xxx'
    if not mlp_params:
        # Set some reasonable mlp parameters
        mlp_params = {}
        mlp_params['layer_sizes'] = [28*28, 500, 500, 11]
        mlp_params['dev_clones'] = 1
        mlp_params['dev_types'] = [1, 1, 2]
        mlp_params['dev_lams'] = [0.1, 0.1, 2.0]
        mlp_params['dev_mix_rate'] = 0.5
        mlp_params['lam_l2a'] = 1e-3
        mlp_params['use_bias'] = 1

    # Initialize a random number generator for this test
    rng = np.random.RandomState(1234)

    # Construct the SS_DEV_NET object that we will be training
    x_in = T.matrix('x_in')
    NET = SS_DEV_NET(rng=rng, input=x_in, params=mlp_params)

    ######################################################
    # First, pretrain each hidden layer in NET as a DAE. #
    ######################################################
    sgd_params['batch_size'] = 100
    sgd_params['start_rate'] = 0.01
    sgd_params['epochs'] = 30
    for i in range(len(NET.mlp_layers)-1):
        print("==================================================")
        print("Pretraining hidden layer {0:d}".format(i+1))
        print("==================================================")
        train_dae(NET, i, mlp_params, sgd_params)

    #########################################################
    # Now, run supervised finetuning on the pretrained mlp. #
    #########################################################
    sgd_params['batch_size'] = 128
    sgd_params['start_rate'] = 0.025
    sgd_params['epochs'] = 500

    # Run semisupervised training on the given MLP
    train_ss_mlp(NET, mlp_params, sgd_params, rng, su_count)

    return 1


def test_dropout_ala_original(mlp_params, sgd_params):
    """Run standard dropout training on MNIST with parameters to reproduce
    the results from original papers by Hinton et. al."""

    # Set suitable optimization parameters
    sgd_params = {}
    sgd_params['start_rate'] = 0.1
    sgd_params['decay_rate'] = 0.998
    sgd_params['wt_norm_bound'] = 3.5
    sgd_params['epochs'] = 1000
    sgd_params['batch_size'] = 100
    sgd_params['result_tag'] = 'dropout'
    sgd_params['mlp_type'] = 'sde' # Use standard dropout

    # Set parameters for the network to be trained
    mlp_params = {}
    mlp_params['layer_sizes'] = [28*28, 800, 800, 11]
    mlp_params['dev_clones'] = 1
    mlp_params['dev_types'] = [1, 1, 2]
    mlp_params['dev_lams'] = [0., 0., 0.]
    mlp_params['dev_mix_rate'] = 0.5
    mlp_params['lam_l2a'] = 0.0
    mlp_params['use_bias'] = 1

    # Initialize a random number generator for this test
    rng = np.random.RandomState(12345)

    # Construct the SS_DEV_NET object that we will be training
    x_in = T.matrix('x_in')
    NET = SS_DEV_NET(rng=rng, input=x_in, params=mlp_params)

    # Initialize biases in each net layer (except final layer) to small
    # positive constants (rather than their default zero initialization)
    for (num, layer) in enumerate(NET.mlp_layers):
        b_init = layer.b.get_value(borrow=False)
        b_const = np.zeros(b_init.shape, dtype=theano.config.floatX)
        if (num < (len(NET.mlp_layers)-1)):
            b_const = b_const + 0.1
        layer.b.set_value(b_const)

    # Run training on the given MLP
    train_mlp(NET, mlp_params, sgd_params)
    return 1

if __name__ == '__main__':

    # Run standard dropout with parameters to reproduce original paper
    #test_dropout_ala_original()

    # Run a single test for measuring semisupervised performance
    test_ss_mlp(sgd_params=False, mlp_params=False, su_count=1000, rng_seed=1248)

    # Run a test of denoising autoencoder training
    #test_dae(dae_layer=0, mlp_params=False, sgd_params=False)

    # Run a test of semisupervised learning with DAE pretraining
    #test_ss_mlp_pt(mlp_params=False, sgd_params=False, su_count=1000)









##############
# EYE BUFFER #
##############
